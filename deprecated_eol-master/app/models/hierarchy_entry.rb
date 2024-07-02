# Represents an entry in the Tree of Life (see Hierarchy).  This is one of the major models of the EOL codebase, and
# most data links to these instances.
class HierarchyEntry < ActiveRecord::Base
  BOGUS_SUFFIX_RE = /^[A-Z][a-z]+ [a-z]{3,}([A-Z0-9_]{2,})/

  belongs_to :hierarchy
  belongs_to :name
  belongs_to :rank
  belongs_to :taxon_concept
  belongs_to :vetted
  belongs_to :visibility
  belongs_to :parent, class_name: "HierarchyEntry", foreign_key: :parent_id

  has_many :agents, through: :agents_hierarchy_entries
  has_many :agents_hierarchy_entries
  has_many :top_images
  has_many :top_unpublished_images
  has_many :synonyms
  has_many :scientific_synonyms, class_name: "Synonym",
      conditions: Proc.new { "synonyms.synonym_relation_id NOT IN (#{SynonymRelation.common_name_ids.join(',')})" }
  has_many :common_names, class_name: "Synonym",
      conditions: Proc.new { "synonyms.synonym_relation_id IN (#{SynonymRelation.common_name_ids.join(',')})" }
  has_many :flattened_ancestors, class_name: "FlatEntry"
  has_many :curator_activity_logs
  has_many :hierarchy_entry_moves
  has_many :curated_data_objects_hierarchy_entries
  has_many :relationships_from, class_name: "HierarchyEntryRelationship",
    inverse_of: :from_hierarchy_entry, foreign_key: "hierarchy_entry_id_1"
  has_many :relationships_to, class_name: "HierarchyEntryRelationship",
    inverse_of: :to_hierarchy_entry, foreign_key: "hierarchy_entry_id_2"

  has_and_belongs_to_many :data_objects
  has_and_belongs_to_many :refs
  has_and_belongs_to_many :published_refs, class_name: Ref.to_s,
    join_table: 'hierarchy_entries_refs',
    association_foreign_key: 'ref_id',
    conditions: Proc.new {
      "published=1 AND visibility_id=#{Visibility.get_visible.id}" }
  has_and_belongs_to_many :flat_ancestors, class_name: HierarchyEntry.to_s,
    join_table: 'hierarchy_entries_flattened',
    association_foreign_key: 'ancestor_id', order: 'lft'
  has_and_belongs_to_many :harvest_events

  has_many :hierarchy_descendants_relationship, class_name: "FlatEntry", foreign_key: 'ancestor_id'

  has_many :descendants, through: :hierarchy_descendants_relationship, source: 'hierarchy_entry'

  # Here is a way to find children and sort by name at the same time (this works for siblings too):
  # HierarchyEntry.find(38802334).children.includes(:name).order('names.string').limit(2)
  has_many :children, class_name: HierarchyEntry.to_s, foreign_key: [:parent_id, :hierarchy_id], primary_key: [:id, :hierarchy_id],
    conditions: Proc.new { "`hierarchy_entries`.`visibility_id` IN (#{Visibility.get_visible.id}, #{Visibility.get_preview.id}) AND `hierarchy_entries`.`parent_id` != 0" }
  # IMPORTANT: siblings will also return the entry itself. This is because it is not possible to use conditions which refer
  # to a single node when using this association in preloading. For example you cannot have a condition: where id != #{id}, because
  # ActiveRecord may not have a single 'id', it may have many if preloading for multiple entries at once. This will also not return siblings of
  # top level taxa. This is because many hierarchies have hundreds or thousands of roots and we don't want to risk showing all of them
  has_many :siblings, class_name: HierarchyEntry.to_s, foreign_key: [:parent_id, :hierarchy_id], primary_key: [:parent_id, :hierarchy_id],
    conditions: Proc.new { "`hierarchy_entries`.`visibility_id` IN (#{Visibility.visible.id}, #{Visibility.preview.id}) AND `hierarchy_entries`.`parent_id` != 0" }

  # Only used when reindexing, to populate solr.
  # TODO: STORE IT IN THE GORRAM TABLE!!!!
  attr_accessor :ancestor_names

  before_save :default_visibility

  counter_culture :hierarchy

  scope :published, -> { where(published: true) }
  scope :visible, -> { where(visibility_id: Visibility.get_visible.id) }
  scope :not_visible, -> { where(["visibility_id != ?",
    Visibility.get_visible.id]) }
  scope :visible_or_preview, -> { where(["visibility_id IN (?)",
    [Visibility.get_visible.id, Visibility.get_preview.id]]) }
  # NOTE: this is a bit different from visible_or_preview; pay attention! Also
  # NOTE that I've had to include the table name in this one because the field
  # names are common. :\
  scope :published_or_preview, -> { where("((hierarchy_entries.published = 1 AND "\
    "hierarchy_entries.visibility_id = #{Visibility.get_visible.id}) OR "\
    "(hierarchy_entries.published = 0 AND hierarchy_entries.visibility_id = "\
    "#{Visibility.get_preview.id}))") }
  scope :not_untrusted, -> { where(["vetted_id != ?", Vetted.untrusted.id]) }
  scope :has_identifier, -> { where("identifier IS NOT NULL AND "\
    "identifier != ''") }
  scope :roots, -> { where(parent_id: 0) }
  scope :active, -> { published.visible.not_untrusted }

  def self.sort_by_name(hierarchy_entries)
    hierarchy_entries.sort_by{ |he| he.name.string.downcase }
  end

  def self.sort_by_vetted(hierarchy_entries)
    hierarchy_entries.sort_by do |he|
      vetted_view_order = he.vetted.blank? ? 0 : he.vetted.view_order
      browsable = he.hierarchy.browsable? ? 0 : 1
      published = he.published? ? 0 : 1
      [published,
       vetted_view_order,
       browsable,
       he.hierarchy.sort_order,
       he.taxon_concept_id,
       he.id]
    end
  end

  # If you want to make a browsable tree of HEs, this might be a helpful method:
  def self.preload_deeply_browsable(set)
    HierarchyEntry.preload_associations(set, [ { agents_hierarchy_entries:
      :agent }, :rank, { hierarchy: :agent } ], select: {hierarchy_entries:
        [:id, :parent_id, :taxon_concept_id]} )
    set
  end

  def self.use_index(which)
    from("#{self.table_name} USE INDEX(#{which})")
  end

  # NOTE: this is unused in the code, but is used manually. Please keep.
  def from_solr
    @entry_solr ||= SolrCore::HierarchyEntries.new
    @entry_solr.connection.
      get("select", params: { q: "id:#{id}" } )["response"]["docs"]
  end

  # NOTE: this is unused in the code, but is used manually. Please keep.
  def relationships_from_solr(limit = 30)
    @rel_solr ||= SolrCore::HierarchyEntryRelationships.new
    @rel_solr.connection.get("select", params: {
      q: "hierarchy_entry_id_1:#{id}", rows: limit })["response"]["docs"]
  end

  def has_parent?
    self.parent_id && self.parent_id.to_i > 0
  end

  # this method will return either the original name string, or if the rank of the taxon
  # is one to be italicized, the italicized form of the original name string
  # This is essentially an italicized, attributed title for the entry.
  def italicized_name
    if name.is_surrogate_or_hybrid? || name.is_subgenus?
      name.string
    else
      species_or_below? ? name.italicized : name.string
    end
  end

  def canonical_form
    return name.canonical_form
  end

  # This is essentially a non-italicized, non-attributed title for the entry.
  def title_canonical
    return @title_canonical unless @title_canonical.nil?
    # used the ranked version first
    if name.is_surrogate_or_hybrid? || name.is_subgenus?
      @title_canonical = name.string.firstcap
    elsif name.ranked_canonical_form && !name.ranked_canonical_form.string.blank?
      @title_canonical = name.ranked_canonical_form.string.firstcap
    # otherwise bare canonical form
    elsif name.canonical_form && !name.canonical_form.string.blank?
      @title_canonical = name.canonical_form.string.firstcap
    # finally just the name string
    elsif name
      @title_canonical = name.string.firstcap
    else
      ""
    end
    @title_canonical
  end

  # takes the result of the above and adds italics tags around it if the
  # taxon is of a rank which should be italicized
  def title_canonical_italicized
    return @title_canonical_italicized unless @title_canonical_italicized.nil?
    @title_canonical_italicized = title_canonical
    # used the ranked version first
    if name.is_surrogate_or_hybrid? || name.is_subgenus?
      # do nothing
    elsif name.ranked_canonical_form && !name.ranked_canonical_form.string.blank?
      @title_canonical_italicized = "<i>#{@title_canonical_italicized}</i>" if
        (species_or_below? || @title_canonical_italicized.match(/ /))
    elsif name.canonical_form && !name.canonical_form.string.blank?
      @title_canonical_italicized = "<i>#{@title_canonical_italicized}</i>" if
        (species_or_below? || @title_canonical_italicized.match(/ /))
    else
      # do nothing
    end
    @title_canonical_italicized
  end

  # NOTE: it is assumed here (for now, TODO) that you have loaded the synonyms,
  # ancestors, and the like before calling this, lest you get a pretty boring
  # hash. See SolrCore::HierarchyEntries for info on how those are populated,
  # but be warned: it's complex. :| TODO: add a for_hash scope...
  def to_hash
    # NOTE the difference here. Kind of absurd... there is precicely zero
    # clarity on where/why the difference is required. The clean form is
    # lowercase, with spaces around parens (and proably other changes that I
    # haven't noticed yet). I am *guessing* this was to make Solr searches
    # cleaner in some way, though how it helps escapes me. Probably something to
    # do with exact word matches.
    canonical = name.clean_canonical_form
    canonical_string = name.canonical_form.string

    if canonical_string =~ BOGUS_SUFFIX_RE
      suffix = $1
      canonical.sub!(suffix, "")
      canonical_string.sub!(suffix, "")
    end

    hash = {
      id: id,
      common_name: synonyms && synonyms.select { |s| s.common_name? }.
        map { |s| SolrCore.string(s.name.string) },
      synonym: synonyms && synonyms.map { |s| SolrCore.string(s.name.string) },
      synonym_canonical: synonyms && synonyms.
        select { |s| s.name && s.name.canonical_form }.
        map { |s| SolrCore.string(s.name.canonical_form.string) },
      parent_id: parent_id,
      taxon_concept_id: taxon_concept_id,
      hierarchy_id: hierarchy_id,
      rank_id: rank_id,
      vetted_id: vetted_id,
      published: published,
      name: SolrCore.string(name.string),
      canonical_form: canonical,
      canonical_form_string: canonical_string
    }
    if ancestor_names
      ancestor_names.keys.each do |key|
        ancestor_names[key] = SolrCore.string(ancestor_names[key])
      end
      hash.merge!(ancestor_names)
    end
    hash
  end

  def rank_label
    @rank_label ||=
      if rank.blank? || rank.label.blank?
        I18n.t(:taxon).firstcap
      else
        rank.label.firstcap
      end
  end

  # wrapper function used in options_from_collection_for_select
  def hierarchy_label
    hierarchy.label
  end

  def hierarchy_provider
    hierarchy_label.presence
  end

  def species_or_below?
    # this was causing a lookup for rank id=0, so I'm trying to save queries
    # here
    return false if rank_id == 0
    return Rank.italicized_ids.include?(rank_id)
  end

  def kingdom
    return ancestors.first rescue nil
  end

  def ancestors
    ancestors = flat_ancestors
    hierarchy.reindex(from: id) if ancestors.empty? and parent_id > 0
    ancestors
  end

  # Some HEs have a "source database" agent, which needs to be considered in
  # addition to normal sources.
  def source_database_agents
    @source_db_agents ||=
      agents_hierarchy_entries.
        select { |ar| ar.agent_role_id == AgentRole.source_database.id }.
        map(&:agent)
  end

  # If a HE *does* have a source database, some behavior changes (we must
  # consider the hierarchy agent source separately), so:
  def has_source_database?
    source_database_agents && ! source_database_agents.empty?
  end

  # These are all of the agents, NOT including the hierarchy agent:
  def source_agents
    agents_hierarchy_entries.
      select { |ar| ar.agent_role_id == AgentRole.source.id }.map(&:agent)
  end

  # This gives you the correct array of source agents that recognize the taxon.
  # Keep in mind that if there is a source database, you MUST cite the hierarchy
  # agent SEPARATELY, so it is not included; otherwise, it is:
  def recognized_by_agents
    if has_source_database?
      (source_database_agents + source_agents).compact
    else
      ([hierarchy.agent] + source_agents).compact
    end
  end

  # This is a full list of AgentsHierarchyEntry models associated with this HE,
  # and should only be used when you know there is no source database (the API
  # code uses this method a lot, at the time of this writing).
  def agents_roles
    ([agent_from_hierarchy] + agents_hierarchy_entries).compact
  end

  # This is only used by #agents_roles, to add it to the list when it's actually
  # there. Don't use this to get an Agent.
  def agent_from_hierarchy
    if h_agent = hierarchy.agent
      # To change the name from just "Catalogue of Life"
      h_agent.full_name = hierarchy.label
      AgentsHierarchyEntry.new(hierarchy_entry: self, agent: h_agent,
                               agent_role: AgentRole.source, view_order: 0)
    else
      nil
    end
  end

  def vet_synonyms(options = {})
    raise "Missing :name_id"     unless options[:name_id]
    raise "Missing :language_id" unless options[:language_id]
    raise "Missing :vetted"      unless options[:vetted]
    Synonym.update_all(
      "vetted_id = #{options[:vetted].id}",
      "language_id = #{options[:language_id]} AND name_id = "\
        "#{options[:name_id]} AND hierarchy_entry_id = #{id}"
    )
  end

  def outlink_hash
    return nil if published != 1 && visibility_id != Visibility.get_visible.id
    if url = outlink_url
      return { hierarchy_entry: self, outlink_url: url }
    end
  end

  def outlink_url
    if !source_url.blank?
      # if the link is Wikipedia this will remove the revision ID
      return source_url.gsub(/&oldid=[0-9]+$/, '')
    elsif hierarchy && !hierarchy.outlink_uri.blank?
      # if the hierarchy outlink_uri expects an ID
      if matches = hierarchy.outlink_uri.match(/%%ID%%/)
        # .. and the ID exists
        unless identifier.blank?
          return hierarchy.outlink_uri.gsub(/%%ID%%/, identifier)
        end
      else
        # there was no %%ID%% pattern in the outlink_uri, but its not blank so
        # its a generic URL for all entries
        return hierarchy.outlink_uri
      end
    end
  end

  def number_of_descendants
    rgt - lft - 1
  end

  #NOTE: THIS IS EXPENSIVE. Use with find_each, and use sparingly.
  def get_descendants
    HierarchyEntry.
      where(["lft BETWEEN ? AND ? AND hierarchy_id = ?",
        lft, rgt, hierarchy_id])
  end

  def is_leaf?
    return (rgt-lft == 1)
  end

  def preferred_classification_summary?
    Rails.cache.exist?(HierarchyEntry.
      cached_name_for("preferred_classification_summary_for_#{self.id}"))
  end

  def preferred_classification_summary
    Rails.cache.fetch(HierarchyEntry.
      cached_name_for("preferred_classification_summary_for_#{self.id}"),
      expires_in: 5.days) do
      root_ancestor, immediate_parent = kingdom_and_immediate_parent
      return '' if root_ancestor.blank?
      str_to_return = root_ancestor.name.string
      str_to_return += " > " + immediate_parent.name.string if immediate_parent
      str_to_return
    end
  end

  def kingdom_and_immediate_parent
    return [ nil, nil ] if flattened_ancestors.blank?
    sorted_ancestors = flattened_ancestors.select { |a| a.ancestor_id != 0 }.
      sort { |a,b| a.ancestor.lft <=> b.ancestor.lft }
    sorted_ancestors.shift if hierarchy == Hierarchy.ncbi
    # sorted ancestors might be blank now
    return [ nil, nil ] if sorted_ancestors.blank?
    root_ancestor = sorted_ancestors.first.ancestor
    immediate_parent = sorted_ancestors.pop.ancestor
    while immediate_parent && immediate_parent != root_ancestor &&
        [ Rank.genus.id, Rank.species.id, Rank.subspecies.id, Rank.variety.id,
          Rank.infraspecies.id ].include?(immediate_parent.rank_id)
      immediate_parent = sorted_ancestors.pop.ancestor
    end
    immediate_parent = nil if immediate_parent == root_ancestor
    [ root_ancestor, immediate_parent ]
  end

  def destroy_everything
    top_images.destroy_all
    # takes too long, prolly not needed: top_unpublished_images.destroy_all
    synonyms.destroy_all
    curator_activity_logs.destroy_all
    hierarchy_entry_moves.destroy_all
    # TODO: handling data objects here. Not doing it now because this is only
    # used from HarvestEvent, and HE handles Datos itself.
    refs.destroy_all
    # Not handling the rest of the tree, here, which I believe is expected.
  end

  private

  def default_visibility
    self.visibility ||= Visibility.get_visible
  end

end
