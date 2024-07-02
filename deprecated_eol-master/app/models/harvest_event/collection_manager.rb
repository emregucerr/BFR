class HarvestEvent
  class CollectionManager
    def self.sync(event)
      manager = new(event)
      manager.sync
    end

    def initialize(event)
      @event = event
    end

    # TODO: something in this process is slow. Figure out what it is and speed
    # it up!
    def sync
      EOL.log("HarvestEvent::CollectionManager.sync ("\
        "http://eol.org/collections/#{collection.id})")
      update_attributes
      add_user_to_collection
      remove_collection_items_not_in_harvest
      index_collection_items_added do
        add_items_to_collection
      end
      EOL::Solr::CollectionItemsCoreRebuilder.reindex_collection(collection, resource: true)
      EOL.log_return
    end

    private

    def add_items_to_collection
      EOL.log_call
      data = []
      harvested_objects_not_already_in_collection.find_each do |object|
        title = object.short_title.gsub("'", "''").gsub(/\\/, "\\\\\\")
        data << "'#{title}', 'DataObject', #{object.id}, #{collection.id}"
      end
      harvested_entries_not_already_in_collection.find_each do |entry|
        name = entry.name.string.gsub("'", "''").gsub(/\\/, "\\\\\\")
        data << "'#{name}', 'TaxonConcept', "\
          "#{entry.taxon_concept_id}, #{collection.id}"
      end
      EOL::Db.bulk_insert(CollectionItem,
        [:name, :collected_item_type, :collected_item_id, :collection_id],
        data, ignore: true)
    end

    def harvested_objects_not_already_in_collection
      @event.data_objects.joins("LEFT JOIN collection_items ci ON "\
          "(data_objects_harvest_events.data_object_id = ci.collected_item_id "\
          "AND ci.collected_item_type = 'DataObject' AND ci.collection_id = "\
          "#{collection.id})").
        includes(:data_type => :translated_data_types).
        where("ci.id IS NULL")
    end

    def harvested_entries_not_already_in_collection
      @event.hierarchy_entries.includes(:name).
        joins("LEFT JOIN collection_items ci ON "\
          "(hierarchy_entries.taxon_concept_id = ci.collected_item_id "\
          "AND ci.collected_item_type = 'TaxonConcept' AND ci.collection_id = "\
          "#{collection.id})").
        where("ci.id IS NULL")
    end

    def collection
      @collection ||= begin
        EOL.log_call
        if resource.collection.nil?
          resource.collection = create_collection_object
          resource.save
        end
        resource.collection
      end
    end

    def content_partner
      resource.content_partner
    end

    def create_collection_object
      Collection.create(
        description: description,
        logo_cache_url: logo_url,
        name: name,
        published: true
      )
    end

    def description
      description = content_partner.description.strip
      description += "." unless description[-1] == "."
      description += " Last indexed #{Date.today.strftime('%b %d, %Y')}"
      description
    end

    def add_user_to_collection
      EOL.log_call
      collection.users << user unless collection.users.include?(user)
    end

    def logo_url
      content_partner.logo_cache_url ||
        user.logo_cache_url
    end

    def name
      resource.title
    end

    def remove_collection_items_not_in_harvest
      EOL.log_call
      ids = CollectionItem.data_objects.
        select("collection_items.id").
        joins("LEFT JOIN data_objects_harvest_events dohe ON "\
          "(collection_items.collected_item_id = dohe.data_object_id "\
          "AND dohe.harvest_event_id = #{@event.id})").
        where(collection_id: collection.id).
        where("data_object_id IS NULL").
        pluck(:id)
      ids += CollectionItem.taxa.
        select("collection_items.id").
        joins("LEFT JOIN (harvest_events_hierarchy_entries hehe JOIN "\
          "hierarchy_entries he ON (hehe.hierarchy_entry_id=he.id AND "\
          "hehe.harvest_event_id = #{@event.id})) ON "\
          "(collection_items.collected_item_id = he.taxon_concept_id)").
        where(collection_id: collection.id).
        where("hehe.hierarchy_entry_id IS NULL").
        pluck(:id)
      CollectionItem.delete(ids)
    end

    def resource
      @event.resource
    end

    def update_attributes
      collection.name = name
      collection.logo_cache_url = logo_url
      collection.description = description
      collection.save if collection.changed?
    end

    def user
      content_partner.user
    end

    # This will be slower than PHP; it's doing a little more thinking (better
    # names).
    def index_collection_items_added(&block)
      EOL.log_call
      max_id = collection.collection_items.maximum(:id) || 0
      yield
      collection.collection_items.where(["id > ?", max_id]).find_in_batches do |batch|
        SolrCore::CollectionItems.reindex_items(
          CollectionItem.preload_collected_items(batch, richness_score: true))
      end
    end
  end
end
