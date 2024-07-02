class TaxonDataExemplar < ActiveRecord::Base

  belongs_to :taxon_concept
  belongs_to :data_point_uri

  attr_accessible :taxon_concept, :taxon_concept_id,  :data_point_uri, :data_point_uri_id, :exclude

  scope :excluded, -> { where(exclude: true) }
  scope :included, -> { where(exclude: false) }

  def self.remove(what)
    TaxonDataExemplar.delete_all(data_point_uri_id: what.id,
                                 taxon_concept_id: what.taxon_concept_id)
  end

  # TODO - Because of warnings, it's not clear to me that this ever actually works.  Check.
  def excluded?
    exclude == true
  end

  # TODO - Because of warnings, it's not clear to me that this ever actually works.  Check.
  def included?
    exclude == false
  end

end
