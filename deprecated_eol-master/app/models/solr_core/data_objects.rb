class SolrCore
  class DataObjects < SolrCore::Base
    CORE_NAME = "data_objects"

    def initialize
      connect(CORE_NAME)
    end

    def delete_by_ids(ids)
      ids = Array(ids)
      exist_ids = []
      # NOTE: Even 500 is too many; request too large. Careful!
      ids.in_groups_of(300, false) do |id_group|
        q = id_group.map { |id| "data_object_id:#{id}" }.join(" OR ")
        response = @connection.paginate(1, 1000, "select", params: { q: q })
        exist_ids += response["response"]["docs"].map { |d| d["data_object_id"] }
      end
      # NOTE: yes, this call is singular (but can take an array)
      @connection.delete_by_query(exist_ids.map { |id| "data_object_id:#{id}" })
      # TODO: error-checking
      @connection.commit
    end

    def best_image_for_page(id)
      paginate("taxon_concept_id:#{id} AND "\
        "data_type_id:#{DataType.image_type_ids.join(" OR data_type_id:")} AND "\
        "published:1 AND visible_ancestor_id:#{id} AND "\
        "(trusted_ancestor_id:#{id} OR unreviewed_ancestor_id:#{id})",
        sort: ["max_visibility_weight desc",
          "max_vetted_weight desc",
          "data_rating desc"],
        per_page: 1)["response"]["docs"].first
    end

    def reindex_hashes(items)
      items = Array(items)
      # EOL.log("SolrCore::DataObjets#reindex_hashes", prefix: '.')
      delete(items.map { |i| "data_object_id:#{i[:data_object_id]}" })
      begin
        @connection.add(items)
      rescue Errno::EPIPE => e # added for iNat, Aug 2016
        EOL.log("Broken pipe while adding #{items.size} items, attempting individually:")
        items.each do |item|
          begin
            @connection.add([item])
          rescue => e
            EOL.log("Failed while adding item: #{item.inspect}")
          end
        end
      end
      @connection.commit
    end
  end
end
