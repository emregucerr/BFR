# Represents a resource's concept of the tree of life, arranged by relationships
require 'invert'

class Hierarchy < ActiveRecord::Base
  # "agent" is the attribution:
  belongs_to :agent
  has_and_belongs_to_many :collection_types
  has_one :resource
  has_one :dwc_resource, class_name: Resource.to_s, foreign_key: :dwc_hierarchy_id
  has_many :hierarchy_entries
  has_many :kingdoms, class_name: HierarchyEntry.to_s, foreign_key: [ :hierarchy_id ], primary_key: [ :id ],
    conditions: Proc.new { "`hierarchy_entries`.`visibility_id` IN (#{Visibility.get_visible.id}, #{Visibility.get_preview.id}) AND `hierarchy_entries`.`parent_id` = 0" }
  has_many :hierarchy_reindexings
  has_many :synonyms, through: :hierarchy_entries

  validates_presence_of :label
  validates_length_of :label, maximum: 255

  before_save :reset_request_publish, if: Proc.new { |hierarchy| hierarchy.browsable == 1 }

  scope :browsable, conditions: { browsable: true }
  scope :nonbrowsable, conditions: { browsable: false }

  alias entries hierarchy_entries

  def self.sort_by_user_or_agent_name(hierarchies)
    hierarchies.sort_by do |h|
      [ h.request_publish ? 0 : 1,
        h.browsable.to_i * -1,
        h.user_or_agent_or_label_name ]
    end
  end

  def self.browsable_by_label
    cached('browsable_by_label') do
      Hierarchy.browsable.sort_by {|h| h.form_label }
    end
  end

  def self.taxonomy_providers
    cached('taxonomy_providers') do
      ['Integrated Taxonomic Information System (ITIS)', 'CU*STAR Classification', 'NCBI Taxonomy', 'Index Fungorum', $DEFAULT_HIERARCHY_NAME].collect{|label| Hierarchy.find_by_label(label, order: "hierarchy_group_version desc")}
    end
  end

  def self.default
    cached_find(:label, $DEFAULT_HIERARCHY_NAME)
  end

  def self.col
    @@col ||= cached('col') do
      Hierarchy.where("label LIKE 'Species 2000 & ITIS Catalogue of Life%%'").includes(:agent).last
    end
  end

  def self.gbif
    # TODO; it's gone ATM and I'm not sure why. :\ Later.
    return nil
    @@gbif ||= cached_find(:label, 'GBIF Nub Taxonomy')
  end

  # This is the first hierarchy we used, and we need it to serve "old" URLs (ie: /taxa/16222828 => Roenbergensis)
  def self.original
    cached_find(:label, "Species 2000 & ITIS Catalogue of Life: Annual Checklist 2007")
  end

  def self.eol_contributors
    Agent # ARRRRRRGH... Dumbest error; can't use the include in tests w/o this.
    @@eol_contributors ||= cached('eol_contributors') do
      Hierarchy.find_by_label("Encyclopedia of Life Contributors", include: :agent)
    end
  end

  def self.iucn_structured_data
    @iucn_structured_data ||= Resource.iucn_structured_data.hierarchy
  end

  def self.ubio
    cached_find(:label, "uBio Namebank")
  end

  def self.ncbi
    @@ncbi ||= cached('ncbi') do
      Hierarchy.find_by_label("NCBI Taxonomy", order: "hierarchy_group_version desc")
    end
  end

  def self.worms
    @@worms ||= cached('worms') do
      Hierarchy.find_by_label("WORMS Species Information (Marine Species)")
    end
  end

  def self.itis
    @@itis ||= cached('itis') do
      Hierarchy.find_by_label('Integrated Taxonomic Information System (ITIS)', order: 'id desc')
    end
  end

  def self.wikipedia
    @@wikipedia ||= cached('wikipedia') do
      Hierarchy.find_by_label('Wikipedia', order: 'id desc')
    end
  end

  def self.browsable_for_concept(taxon_concept)
    Hierarchy.joins(:hierarchy_entries).select('hierarchies.id, hierarchies.label, hierarchies.descriptive_label').
      where(['hierarchies.browsable = 1 AND hierarchy_entries.taxon_concept_id = ?', taxon_concept.id])
  end

  def self.available_via_api
    available_hierarchies = Hierarchy.browsable
    available_hierarchies << Hierarchy.gbif if Hierarchy.gbif
    available_hierarchies.sort_by(&:id)
  end

  def sort_order
    return 1 if self == Hierarchy.col
    return 2 if self == Hierarchy.itis
    return 3 if self.label == 'Avibase - IOC World Bird Names (2011)'
    return 4 if self.label == 'WORMS Species Information (Marine Species)'
    return 5 if self.label == 'FishBase (Fish Species)'
    return 6 if self.label == 'IUCN Red List (Species Assessed for Global Conservation)'
    return 7 if self.label == 'Index Fungorum'
    return 8 if self.label == 'Paleobiology Database'
    9999
  end

  # NOTE: this assumes the "leaf" nodes *are* published.
  def publish_ancestors
    set = HierarchyEntry.where(hierarchy_id: id).published
    while ids = set.pluck(:parent_id) do
      ids.delete(0)
      break if ids.empty?
      set = HierarchyEntry.where(id: ids)
      set.where(published: false).update_all(published: true)
    end
  end

  def flatten
    Hierarchy::Flattener.flatten(self)
  end

  def form_label
    return descriptive_label unless descriptive_label.blank?
    return label
  end

  def content_partner
    # the resource has a content partner
    if resource && resource.content_partner
      resource.content_partner
    # there is an archive resource, which has a content_partner
    elsif dwc_resource && dwc_resource.content_partner
      dwc_resource.content_partner
    # the hierarchy has no resource, but it has an agent which has a user which has content partners
    elsif agent.user && !agent.user.content_partners.blank?
      agent.user.content_partners.first
    end
  end

  def merge_matching_concepts
    Hierarchy::ConceptMerger.merges_for_hierarchy(self)
  end

  # NOTE: this is only called manually. Pleas keep.
  def relate
    resource.harvest_events.last.relate_new_hierarchy_entries
  end

  # NOTE: this is not called in the code, but it's use manually. Please keep.
  def reindex_and_merge_ids(ids)
    SolrCore::HierarchyEntries.reindex_hierarchy(self, ids: ids)
    Hierarchy::Relator.relate(self, entry_ids: ids)
    Hierarchy::ConceptMerger.merges_for_hierarchy(self, ids: ids)
  end

  # Returns (a potentially VERY large) array of ids that were previously
  # published.
  def unpublish
    EOL.log_call
    ids = unpublish_and_hide_hierarchy_entries
    unpublish_synonyms
    ids
  end

  def request_to_publish_can_be_made?
    !self.browsable? && !request_publish
  end

  def user_or_agent
    if resource && resource.content_partner && resource.content_partner.user
      resource.content_partner.user
    elsif agent
      agent
    else
      nil
    end
  end

  def user_or_agent_or_label_name
    if user_or_agent
      user_or_agent.full_name
    else
      label
    end
  end

  def display_title
    if resource
      resource.title
    elsif dwc_resource
      dwc_resource.title
    else
      user_or_agent_or_label_name
    end
  end

  def reindex(options = {})
    HierarchyReindexing.enqueue_unless_pending(self, options)
  end

  def insert_data_objects_taxon_concepts
    EOL.log_call
    self.class.connection.
      execute(insert_dot_dohe_query("data_objects_hierarchy_entries"))
    EOL.log("curated", prefix: ".")
    self.class.connection.
      execute(insert_dot_dohe_query("curated_data_objects_hierarchy_entries"))
    EOL.log("done", prefix: ".")
  end

  def ancestry_set
    @ancestry_set ||= FlatEntry.where(hierarchy_id: id)
  end

  def clear_ancestry_set
    @ancestry_set = nil
  end

private

  # There's no nice way to do this in Rails and can be super slow if you don't
  # use the INSERT SELECT!
  def insert_dot_dohe_query(table)
    "INSERT IGNORE INTO data_objects_taxon_concepts (`taxon_concept_id`, "\
    "`data_object_id`) SELECT taxon_concepts.id, data_objects.id FROM "\
    "taxon_concepts JOIN hierarchy_entries ON (taxon_concepts.id = "\
    "hierarchy_entries.taxon_concept_id AND hierarchy_entries.hierarchy_id = "\
    "#{id}) JOIN #{table} ON "\
    "(#{table}.hierarchy_entry_id = hierarchy_entries.id) "\
    "JOIN data_objects ON (#{table}.data_object_id = "\
    "data_objects.id) WHERE (data_objects.published = 1 OR "\
    "#{table}.visibility_id != #{Visibility.get_visible.id})"
  end

  def reset_request_publish
    self.request_publish = false
    return true
  end

  def unpublish_and_hide_hierarchy_entries
    entry_ids = hierarchy_entries.where(published: true).pluck(:id)
    hierarchy_entries.where(id: entry_ids).
      update_all(published: false, visibility_id: Visibility.get_invisible.id)
    entry_ids
  end

  def unpublish_synonyms
    synonyms.where(synonyms: { published: true }).
      update_all(["synonyms.published = ?", false])
  end

end
