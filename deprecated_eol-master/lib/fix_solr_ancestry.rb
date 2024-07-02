class FixSolrAncestry
  def self.site_search
    @solr = SolrCore::SiteSearch.new
    paginator = SolrCore::TimedPaginator.new(@solr,
      "ancestor_taxon_concept_id:[* TO *] AND resource_type:TaxonConcept")
    paginator.paginate do |docs|
      taxa = TaxonConcept.where(id: docs.map { |r| r["resource_id"] }).
        includes(:flattened_ancestors)
      delete_these = []
      bad = []
      docs.each do |doc|
        taxon = taxa.find { |t| t.id == doc["resource_id"] }
        unless taxon
          delete_these << doc["resource_id"]
          next
        end
        d_ancestors = doc["ancestor_taxon_concept_id"].sort
        t_ancestors = taxon.flattened_ancestors.map(&:ancestor_id).sort.uniq
        # 0 never matters, just ignore it:
        d_ancestors.delete(0)
        t_ancestors.delete(0)
        if d_ancestors != t_ancestors
          # doc.symbolize_keys!
          # doc[:ancestor_taxon_concept_id] = t_ancestors
          # doc.delete(:keyword_cn)
          # doc.delete(:keyword_ar)
          bad << taxon.id
        end
      end
      # NOTE these are ONLY deleted, not added (they are missing)
      unless delete_these.empty?
        EOL.log("Deleting #{delete_these.size} missing taxa from Solr")
        @solr.delete_batch(TaxonConcept, delete_these)
      end
      # NOT WORKING: Argh.
      # bad.each do |b|
      #   puts "resource_id:#{b[:resource_id]} AND resource_type:#{b[:resource_type]} AND keyword_type:#{b[:keyword_type]}"
      #   @solr.delete("resource_id:#{b[:resource_id]} AND resource_type:#{b[:resource_type]} AND keyword_type:#{b[:keyword_type]}")
      # end
      # @solr.connection.add(bad)

      # NOTE this method deletes the ids it needs to. Also NOTE that this will
      # re-load the taxa, somewhat inefficiently. Alas, I couldn't find a way to
      # just change a row and re-insert. It didn't work for some reason. :S
      EOL.log("Replacing #{bad.size} Solr entries: #{bad.join(",")}")
      @solr.insert_batch(TaxonConcept, bad) #.map { |b| b[:resource_id] })
    end
  end
end
