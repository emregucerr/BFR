class PageName < ActiveRecord::Base
  belongs_to :item_page
  belongs_to :name
  self.primary_keys = :name_id, :item_page_id
  
  def self.page_names_for?(taxon_concept_id)
    return PageName.count_by_sql(['SELECT 1 FROM taxon_concept_names tcn 
                                     STRAIGHT_JOIN page_names pn 
                                    ON (tcn.name_id=pn.name_id) 
                                    WHERE tcn.taxon_concept_id = ? AND vern=0
                                    LIMIT 1', taxon_concept_id]) > 0
  end
      

  
end
# == Schema Info
# Schema version: 20081020144900
#
# Table name: page_names
#
#  item_page_id :integer(4)      not null
#  name_id      :integer(4)      not null

