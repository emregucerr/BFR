class Resource
  class Publisher
    attr_reader :resource, :harvest_event

    def self.publish(resource, options = {})
      publisher = self.new(resource)
      publisher.publish(options)
    end

    def initialize(resource)
      ActiveRecord::Base.with_master do
        @resource = resource
        @event = resource.harvest_events.last
        raise "No hierarchy!" unless @resource.hierarchy
      end
    end

    # NOTE: yes, PHP used multiple transactions. I suppose it was to avoid
    # locking the DB for too long, but I wonder if it was wise? TODO: consider
    # whether we acutally _need_ transactions! ...We can assume the HEs that
    # we're working on are not being touched... the worst that might happen is
    # curation of something that gets missed here, but we might be able to
    # capture that in another way. NOTE: This _requires_ that the flattened
    # hierarchy have been rebuilt when this is called.
    def publish(options = {})
      EOL.log("PUBLISH STARTING: #{@resource}", prefix: "{")
      unless options[:force]
        raise EOL::Exceptions::HarvestNotReady.new("Event already published!") if
          @event.published?
        raise EOL::Exceptions::HarvestNotReady.new("Event not complete!") unless
          @event.complete?
        raise EOL::Exceptions::HarvestNotReady.new("Publish flag not set!") unless
          @event.publish?
      end
      # Critically important to read from master!
      ActiveRecord::Base.with_master do
        # PHP doesn't seem to be doing this anymore:
        @resource.hierarchy.publish_ancestors
        @resource.flatten
        @event.publish_affected
        # NOTE: the next two steps comprise the lion's share of publishing time.
        # The indexing (usually) takes considerably more time than the merging.
        @resource.index_for_merges
        @event.merge_matching_concepts
        @resource.rebuild_taxon_concept_names
        @event.sync_collection
        @resource.publish_traitbank
        @event.index
        @resource.mark_as_published
        @resource.save_resource_contributions
        @resource.hierarchy.insert_data_objects_taxon_concepts
        # TODO: this next command could, technically, leave zombie entries. We
        # need to add a step that says "delete all entries in dotoc where ids in
        # (list of ids that were in previous event but not this one)"
        @event.insert_dotocs
      end
      EOL.log("PUBLISH DONE: #{resource.title}", prefix: "}")
      true
    end
  end
end
