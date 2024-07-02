class PageJson < ActiveRecord::Base
  @MAX_AGE = 6.months

  serialize :ld, JSON
  serialize :context, JSON

  attr_accessible :ld, :context, :page_id

  belongs_to :page, class_name: "TaxonConcept", foreign_key: "page_id", inverse_of: :page_json

  def self.for(page_id, page_traits = nil)
    PageJson.with_master do
      if PageJson.exists?(page_id: page_id)
        pj = PageJson.find_by_page_id(page_id)
        if pj.updated_at < @MAX_AGE.ago
          pj.build_json(page_traits)
          pj.save
        end
        pj
      else
        pj = PageJson.new(page_id: page_id)
        pj.build_json(page_traits)
        pj.save
        pj
      end
    end
  end

  def build_json(page_traits = nil)
    page_traits ||= PageTraits.new(self[:page_id])
    self[:ld] =
      TraitBank::JsonLd.data_feed_item(self[:page_id], page_traits.traits)
    self[:context] = TraitBank::JsonLd.page_context(page_traits.glossary)
  end

  def has_traits?
    ld["item"] && ld["item"]["traits"] && ! ld["item"]["traits"].empty?
  end
end
