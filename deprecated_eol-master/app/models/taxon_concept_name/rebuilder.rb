class TaxonConceptName
  # As I note in the main TCN class... TCN is ... weird. A conglomeration of
  # multiple types of names. It's not clearly designed, it's not clear (at all)
  # to use, and it's certainly not clear to build. This needs serious
  # re-thinking.
  class Rebuilder
    def self.by_taxon_concept_id(ids)
      rebuilder = new
      rebuilder.by_taxon_concept_id(ids)
    end

    def initialize
      # Nothing to do, really. We don't know what we're going to work on.
    end

    def by_taxon_concept_id(tc_ids)
      EOL.log("TaxonConceptName::Rebuilder.by_taxon_concept_id")
      tc_ids = Array(tc_ids)
      size = tc_ids.size
      index = 0
      tc_ids.in_groups_of(500, false) do |ids|
        index += ids.size
        EOL.log("Rebuilding names: #{index} taxa of #{size}")
        rebuild_tc_ids(ids)
        sleep(0.1) # Let's not throttle the DB.
      end
    end

    def rebuild_tc_ids(tc_ids)
      preferred = HierarchyEntry.published_or_preview.
        where(["taxon_concept_id IN (?)", tc_ids])
      synonyms = Synonym.not_common_names.joins(:hierarchy_entry).
        includes(:hierarchy_entry).
        merge(HierarchyEntry.published_or_preview).
        where(["taxon_concept_id IN (?)", tc_ids])
      get_name_ids(preferred, synonyms)
      get_matching_ids(preferred, synonyms)
      # This uses matching_ids (in part) to flesh out name_ids:
      get_canonical_form_name_ids
      # This also populates @preferred_in_language (they are related)
      get_common_names(tc_ids)
      ensure_languages_have_a_preferred_name
      sci_names = prepare_scientific_names
      common = prepare_common_names
      # NOTE: this removes both scientific AND common!
      delete_existing_taxon_concept_names(tc_ids)
      insert_scientific_names(sci_names)
      insert_common_names(common)
    end

    def get_name_ids(preferred, synonyms)
      @taxa_by_synonym = {}
      get_preferred_name_ids(preferred)
      get_synonym_name_ids(synonyms)
      raise("No name IDs found...") if @taxa_by_synonym.empty?
    end

    def get_preferred_name_ids(entries)
      entries.each do |entry|
        @taxa_by_synonym[entry.id] ||= Set.new
        @taxa_by_synonym[entry.id] << entry.taxon_concept_id
      end
    end

    def get_synonym_name_ids(synonyms)
      synonyms.each do |synonym|
        @taxa_by_synonym[synonym.id] ||= Set.new
        @taxa_by_synonym[synonym.id] << synonym.hierarchy_entry.taxon_concept_id
      end
    end

    # Keys on matching_ids are TC ids, values are a hash. The value hash has a
    # name_id as the key and another hash as the value. That value hash (!)
    # has a hierarchy entry ID as the key, and a type (:preferred/:synonym) as
    # the value. This reads kind of like "for taxon concetps, these names have
    # relationships to these hierarchy entries as [a synonym / a preferred
    # name]"
    def get_matching_ids(preferred, synonyms)
      @matching_ids = {}
      get_preferred_matching_ids(preferred)
      get_synonym_matching_ids(synonyms)
    end

    def get_preferred_matching_ids(preferred)
      preferred.each do |entry|
        @matching_ids[entry.taxon_concept_id] ||= {}
        @matching_ids[entry.taxon_concept_id][entry.name_id] ||= {}
        @matching_ids[entry.taxon_concept_id][entry.name_id][entry.id] =
          :preferred
      end
    end

    def get_synonym_matching_ids(synonyms)
      synonyms.each do |synonym|
        tc_id = synonym.hierarchy_entry.taxon_concept_id
        @matching_ids[tc_id] ||= {}
        @matching_ids[tc_id][synonym.name_id] ||= {}
        @matching_ids[tc_id][synonym.name_id][synonym.hierarchy_entry_id] =
          :synonym
      end
    end

    def get_canonical_form_name_ids
      # NOTE: this weird join is kind of "round-tripping", making sure that the
      # string on the canonical form is the same as the string on the original
      # name. I'm not sure why the PHP code did this. (?)
      Name.joins(canonical_form: [ :names ]).
        select("names.id, names_canonical_forms.id canonical_name_id").
        where(["names.id IN (?) AND "\
          "names_canonical_forms.string = canonical_forms.string",
          @taxa_by_synonym.keys]).
        find_each do |name|
        unless name.id == name["canonical_name_id"]
          @taxa_by_synonym[name.id].each do |tc_id|
            @matching_ids[tc_id] ||= {}
            @matching_ids[tc_id][name["canonical_name_id"]] ||= {}
            # NOTE: this is implying (by using 0) that there is no
            # source_hierarchy_entry_id. As of this writing, there were 6.6M
            # names in TCN of this sort (out of 25M), so... quite a few! The
            # use of :synonym as the value here is bizzarre. The PHP code
            # actually had this set to :preferred (well, technically, 1, but I
            # though that was unclear), but then the code that wrote it to the
            # DB ignored that value and forced it to be 0. Since that's the
            # way it's been since time began, I'm going to keep it that way,
            # and just make it clearer here that it will NOT be preferred:
            @matching_ids[tc_id][name["canonical_name_id"]][0] = :synonym
          end
        end
      end
    end

    def get_common_names(tc_ids)
      @common_names = {}
      @preferred_in_language = {}
      Synonym.common_names.
        joins(:hierarchy_entry, :vetted).
        includes(:hierarchy_entry).
        where(["taxon_concept_id IN (?)", tc_ids]).
        # Ugh. :|
        order("language_id, (synonyms.hierarchy_id = " +
          Hierarchy.eol_contributors.id.to_s +
          ") DESC, view_order ASC, preferred DESC, synonyms.id DESC").
        find_each do |synonym|
        study_synonym(synonym)
      end
    end

    def study_synonym(synonym)
      tc_id = synonym.hierarchy_entry.taxon_concept_id
      preferred = synonym.preferred
      # TODO: Don't hard-code this! :( Should be a flag on hierarchy called
      # "ignore_common_names" or the like.
      return if synonym.hierarchy_id == Hierarchy.wikipedia.try(:id)
      is_curator_name = synonym.hierarchy_id ==
        Hierarchy.eol_contributors.try(:id)
      # TODO: Don't hard-code this! Add a "check_unpublished_names" column...
      check_unpublished_names = synonym.hierarchy_id == Hierarchy.ubio.try(:id)
      @preferred_in_language[tc_id] ||= {}
      if is_curator_name || check_unpublished_names ||
        ( synonym.hierarchy_entry.published? &&
          synonym.hierarchy_entry.visibility_id == Visibility.get_visible.id )
        # NOTE: yes, this really is has_key? and does NOT check the value of the
        # boolean. I think this is trying to say "this one can't be preferred if
        # we already have a preferred entry in this language."
        preferred = false if
          @preferred_in_language[tc_id].has_key?(synonym.language_id)
        if preferred && is_curator_name && not_untrusted?(synonym.vetted_id)
          @preferred_in_language[tc_id][synonym.language_id] = true
        else
          preferred = false
        end
        @common_names[tc_id] ||= []
        @common_names[tc_id] << {
          synonym_id: synonym.id,
          language_id: synonym.language_id,
          name_id: synonym.name_id,
          hierarchy_entry_id: synonym.hierarchy_entry_id,
          preferred: preferred,
          vetted_id: synonym.vetted_id,
          is_curator_name: is_curator_name
        }
      end
    end

    def ensure_languages_have_a_preferred_name
      @common_names.each do |tc_id, common_name_hashes|
        common_name_hashes.each_with_index do |common_name_h, index|
          if there_was_no_preferred_name(tc_id, common_name_h[:language_id]) &&
            not_untrusted?(common_name_h[:vetted_id])
            @common_names[tc_id][index][:preferred] = true
            @preferred_in_language[tc_id][common_name_h[:language_id]] = true
          end
        end
      end
    end

    def prepare_scientific_names
      data = Set.new
      @matching_ids.each do |tc_id, names|
        names.each do |name_id, entries|
          entries.each do |entry_id, type|
            preferred = entry_id && type == :preferred
            data << "#{tc_id},#{name_id},#{entry_id},0,0,#{preferred ? 1 : 0}"
          end
        end
      end
      data
    end

    def delete_existing_taxon_concept_names(tc_ids)
      TaxonConceptName.where(taxon_concept_id: tc_ids).delete_all
    end

    def insert_scientific_names(data)
      EOL.log("Inserting #{data.size} scientific names...")
      EOL::Db.bulk_insert(TaxonConceptName,
        # NOTE: PHP didn't bother with the last two fields, synonym_id and
        # vetted_id. I guess that means scientific names are always considered
        # vetted and don't use the synonym_id (which makes sense—it's not
        # actually a synonym and it's not a common name, which is stored in the
        # synonyms table...)
        [:taxon_concept_id, :name_id, :source_hierarchy_entry_id, :language_id,
          :vern, :preferred],
        data.to_a, silent: true)
    end

    def prepare_common_names
      data = Set.new
      @common_names.each do |tc_id, common_names|
        common_names.each do |name|
          data << "#{tc_id},#{name[:name_id]},#{name[:hierarchy_entry_id]},"\
            "#{name[:language_id]},1,#{name[:preferred] ? 1 : 0},"\
            "#{name[:synonym_id]},#{name[:vetted_id]}"
        end
      end
      data
    end

    def insert_common_names(data)
      EOL.log("Inserting #{data.size} scientific names...")
      EOL::Db.bulk_insert(TaxonConceptName,
        [:taxon_concept_id, :name_id, :source_hierarchy_entry_id, :language_id,
          :vern, :preferred, :synonym_id, :vetted_id],
        data.to_a, silent: true)
    end

    def there_was_no_preferred_name(tc_id, language_id)
      ! @preferred_in_language[tc_id][language_id]
    end

    def not_untrusted?(vet_id)
      [Vetted.trusted.id, Vetted.unknown.id].include?(vet_id)
    end
  end
end
