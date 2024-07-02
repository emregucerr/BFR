class HarvestEvent
  class SiteSearchIndexer
    def self.index(event)
      indexer = self.new(event)
      indexer.index
    end

    def initialize(event)
      @harvest_event = event
      @solr = SolrCore::SiteSearch.new
    end

    # TODO: really, we should be able to check whether that's been
    # done and call it if not; worth adding a flag to the DB to indicate that.
    # NOTE: there is a terribly inefficiency here too, if nothing has changed
    # about the taxon. ...we end up building it anyway, which is horribly slow.
    def index
      dids = @harvest_event.new_data_object_ids
      tids = HierarchyEntry.
        where(id: @harvest_event.hierarchy_entries.pluck(:id)).
        pluck(:taxon_concept_id)
      EOL.log("HarvestEvent::SiteSearchIndexer#index (#{dids.size} media, "\
        "#{tids.size} taxa)")
      @solr.index_type(DataObject, dids)
      @solr.index_type(TaxonConcept, tids)
    end
  end
end
