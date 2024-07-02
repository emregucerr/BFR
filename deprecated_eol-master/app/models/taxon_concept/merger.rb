class TaxonConcept
  # NOTE: this does not update collection items. You may wish to do so. ...Among
  # many other things (see various denormalization functions, in TODOs). Sigh.
  # NOTE: you may wish to run this in a transaction (if you aren't in one
  # already); that is the _caller's_ responsibility. ...but note that changes to
  # Solr aren't necessarily synced. NOTE: this returns the SUPERCEDED
  # TaxonConcept!!! Why? So you can see both the id that was superceded as well
  # as the supercedure_id to see where it went. If you're calling this, you
  # probably care about both.
  class Merger
    # TODO: RandomHierarchyImage should be scanned and updated, too!
    class << self
      def in_bulk(raw_merges)
        ids = Set.new
        merges = {}
        concepts = {}
        # NOTE raw_merges is keyed on the old id; we want one keyed on new IDs.
        raw_merges.each do |old_id, new_id|
          while raw_merges.has_key?(new_id)
            # Chain merge! ...We want the ultimate destination:
            new_id = raw_merges[new_id]
          end
          merges[new_id] ||= []
          merges[new_id] << old_id
          ids += [old_id, new_id]
        end
        ids.to_a.in_groups_of(10_000, false) do |group|
          TaxonConcept.with_titles.where(id: group).each do |concept|
            concepts[concept.id] = concept
          end
        end
        concepts.values.select { |c| ! c.published? }.each do |concept|
          if merges.has_key?(concept.id)
            lost = merges.delete(concept.id)
            EOL.log("WARNING: Cannot merge taxa (#{lost.join(", ")}) to "\
              "UNPUBLISHED taxon #{concept.id}")
          end
        end
        reindex_concepts = []
        num_merges = merges.keys.size
        EOL.log("Have #{num_merges} merges...") unless num_merges <= 0
        merges.each do |to_id, from_ids|
          to_concept = concepts[to_id]
          if to_concept.nil?
            EOL.log("ERROR: Missing target concept! (#{from_ids.join(", ")}) "\
              "=> #{to_id}", prefix: "!")
            next
          end
          from_concepts = []
          from_ids.each do |id|
            if concepts.has_key?(id)
              from_concepts << concepts[id]
            else
              EOL.log("WARNING: Missing source concept (#{id})!", prefix: "*")
            end
          end
          if from_concepts.empty?
            EOL.log("WARNING: No source concepts to merge to #{to_id}!",
              prefix: "*")
            next
          elsif from_concepts.size == 1
            begin
              taxon_concepts(to_concept, from_concepts.first,
                skip_reindex: true)
              reindex_concepts << to_concept
              EOL.log("MERGE: #{from_concepts.first} => #{to_concept}")
            rescue => e
              EOL.log("SKIP MERGE #{from_concepts.first} => #{to_concept}: "\
                "#{e.message}", prefix: "*")
            end
          else
            # Note the #map because we may have lost one or two, so NOT from_ids:
            multiple_concepts(to_concept.id, from_concepts.map(&:id))
            reindex_concepts << to_concept
            EOL.log("MERGE multiple to #{to_concept}:")
            from_concepts.each { |c| EOL.log("  ... #{c}") }
          end
        end
        # Second pass; now we're done mucking with Solr, so let PHP have at it:
        reindex_concepts.each do |concept|
          TaxonConceptReindexing.reindex(concept, allow_large_tree: true)
        end
        return num_merges
      end

      # NOTE: if you watch the logs, you will see a lot of individual
      # TaxonConcept loads, which would be nice to avoid, but until we have a
      # "bulk merger" class, this is the safest way to do it!
      def ids(id1, id2)
        # Always take the LOWEST id first; id1 is "kept", id2 "goes away"
        (id1, id2) = [id1, id2].sort
        new_concept = TaxonConcept.find_without_supercedure(id1)
        return new_concept if id1 == id2
        raise "Missing an ID (#{id1}, #{id2})" if id1 <= 0
        raise EOL::Exceptions::MergeToUnpublishedTaxon unless new_concept.published?
        old_concept = TaxonConcept.find_without_supercedure(id2)
        raise "Missing source concept (#{id2})" unless old_concept
        EOL.log("MERGE: concept #{id2} into #{id1}")
        taxon_concepts(new_concept, old_concept)
      end

      def taxon_concepts(new_concept, old_concept, options = {})
        new_id = new_concept.id
        old_id = old_concept.id
        raise "Wrong IDs!" if new_id > old_id
        old_concept.update_attributes(supercedure_id: new_id, published: false)
        HierarchyEntry.where(taxon_concept_id: old_id).
          update_all(taxon_concept_id: new_id)
        UsersDataObject.where(taxon_concept_id: old_id).
          update_all(taxon_concept_id:new_id)
        # TODO: these don't actually delete records that need to be deleted. This
        # algorithm is wrong.
        update_ignore_id(TaxonConceptName, new_id, old_id)
        update_ignore_id(DataObjectsTaxonConcept, new_id, old_id)

        update_ignore_id(FlatTaxon, new_id, old_id)
        update_ignore_ancestor_id(FlatTaxon, new_id, old_id)
        move_traits(new_id, old_id)
        # Removing the old item is NOT handled by reindexing:
        @solr = SolrCore::SiteSearch.new
        @solr.delete_item(old_concept)
        # Handles the rest:
        TaxonConceptReindexing.reindex(new_concept) unless options[:skip_reindex]
        # NOTE: this one used to also do a join to hierarchy_entries and ensure that
        # the tc id was old_id. ...But that has already changed by this point, sooo...
        # that never worked. :| Also, it seems entirely superfluous. Just using the
        # tc id on that table:
        update_ignore_id(RandomHierarchyImage, new_id, old_id)
        old_concept
      end

      # NOTE: DOES NOT reindex items!
      def multiple_concepts(new_id, old_ids)
        old_concepts = TaxonConcept.where(id: old_ids)
        old_concepts.update_all(supercedure_id: new_id, published: false)
        HierarchyEntry.where(taxon_concept_id: old_ids).
          update_all(taxon_concept_id: new_id)
        UsersDataObject.where(taxon_concept_id: old_ids).
          update_all(taxon_concept_id:new_id)
        # TODO: these don't actually delete records that need to be deleted. This
        # algorithm is wrong.
        update_ignore_ids(TaxonConceptName, new_id, old_ids)
        update_ignore_ids(DataObjectsTaxonConcept, new_id, old_ids)
        update_ignore_ids(FlatTaxon, new_id, old_ids)
        update_ignore_ancestor_ids(FlatTaxon, new_id, old_ids)
        old_ids.each do |old_id|
          move_traits(new_id, old_id)
        end
        # Removing the old items is NOT handled by reindexing:
        @solr = SolrCore::SiteSearch.new
        @solr.delete_batch(TaxonConcept, old_ids)
        # NOTE: this one used to also do a join to hierarchy_entries and ensure that
        # the tc id was old_id. ...But that has already changed by this point, sooo...
        # that never worked. :| Also, it seems entirely superfluous. Just using the
        # tc id on that table:
        update_ignore_ids(RandomHierarchyImage, new_id, old_ids)
      end

      def move_traits(new_id, old_id)
        traits = TraitBank.page_traits(old_id)
        clauses = []
        traits.each do |trait|
          clauses << "#{trait[:predicate].to_ntriples} #{trait[:trait].to_ntriples}"
        end
        old_traits = clauses.map { |c| "<http://eol.org/pages/#{old_id}> #{c}" }
        # TODO: we still need a delete method...
        del_q = "WITH GRAPH <#{TraitBank.graph}> DELETE "\
        "{ #{old_traits.join(" . ")} } WHERE { #{old_traits.join(" . ")} }"
        begin
          TraitBank.connection.query(del_q)
        rescue EOL::Exceptions::SparqlDataEmpty => e
          # Do nothing... this is acceptable for a delete...
        end
        new_traits = clauses.map { |c| "<http://eol.org/pages/#{new_id}> #{c}" }
        TraitBank.connection.insert_data(data: new_traits,
        graph_name: TraitBank.graph)
      end

      # TODO: Rails doesn't have a way to UPDATE IGNORE ... WTF?
      def update_ignore_id(klass, id1, id2)
        EOL::Db.update_ignore_id_by_field(klass, id1, id2, "taxon_concept_id")
      end

      def update_ignore_ancestor_id(klass, id1, id2)
        EOL::Db.update_ignore_id_by_field(klass, id1, id2, "ancestor_id")
      end

      def update_ignore_ids(klass, id1, ids)
        EOL::Db.update_ignore_ids_by_field(klass, id1, ids, "taxon_concept_id")
      end

      def update_ignore_ancestor_ids(klass, id1, ids)
        EOL::Db.update_ignore_ids_by_field(klass, id1, ids, "ancestor_id")
      end
    end
  end
end
