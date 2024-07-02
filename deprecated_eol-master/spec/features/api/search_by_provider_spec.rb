require File.dirname(__FILE__) + '/../../spec_helper'

describe 'API:search_by_provider' do
  before(:all) do
    load_foundation_cache
    @test_hierarchy = Hierarchy.gen(label: 'Some test hierarchy', browsable: 1)
    @test_hierarchy_entry_published = HierarchyEntry.gen(hierarchy: @test_hierarchy, identifier: 'Animalia',
      parent_id: 0, published: 1, visibility_id: Visibility.visible.id, rank: Rank.kingdom)
    @test_hierarchy_entry_unpublished = HierarchyEntry.gen(hierarchy: @test_hierarchy, identifier: 'Plantae',
      parent_id: 0, published: 0, visibility_id: Visibility.invisible.id, rank: Rank.kingdom)
  end
  
  # not logging API anymore!
  # it 'should create an API log including API key' do
    # user = User.gen(api_key: User.generate_key)
    # check_api_key("/api/search_by_provider/#{@test_hierarchy_entry_unpublished.identifier}.json?hierarchy_id=#{@test_hierarchy_entry_unpublished.hierarchy_id}&key=#{user.api_key}", user)
  # end

  it 'search_by_provider should return the EOL page ID for a provider identifer' do
    response = get_as_xml("/api/search_by_provider/#{@test_hierarchy_entry_published.identifier}.xml?hierarchy_id=#{@test_hierarchy_entry_published.hierarchy_id}")
    our_result = response.xpath("//eol_page_id")
    our_result.length.should == 1
    our_result.inner_text.to_i.should == @test_hierarchy_entry_published.taxon_concept_id

    response = get_as_json("/api/search_by_provider/#{@test_hierarchy_entry_published.identifier}.json?hierarchy_id=#{@test_hierarchy_entry_published.hierarchy_id}")
    response.length.should > 0
    response.collect{ |r| r['eol_page_id'].to_i == @test_hierarchy_entry_published.taxon_concept_id}.length == 1
  end
  
  it 'search_by_provider should return the EOL page link for a provider identifer' do
    response = get_as_xml("/api/search_by_provider/#{@test_hierarchy_entry_published.identifier}?hierarchy_id=#{@test_hierarchy_entry_published.hierarchy_id}")
    our_result = response.xpath("//eol_page_link")
    our_result.inner_text.should == "#{Rails.configuration.site_domain}/pages/#{@test_hierarchy_entry_published.taxon_concept_id}"

    response = get_as_json("/api/search_by_provider/#{@test_hierarchy_entry_published.identifier}.json?hierarchy_id=#{@test_hierarchy_entry_published.hierarchy_id}")
    response.length.should > 0
    response.collect{ |r| r['eol_page_link'] == "#{Rails.configuration.site_domain}/pages/#{@test_hierarchy_entry_published.taxon_concept_id}"}.length == 1
  end

  it 'search_by_provider should not return the EOL page ID for a provider identifer' do
    response = get_as_xml("/api/search_by_provider/#{@test_hierarchy_entry_unpublished.identifier}?hierarchy_id=#{@test_hierarchy_entry_unpublished.hierarchy_id}")
    our_result = response.xpath("//eol_page_id")
    our_result.length.should == 0

    response = get_as_json("/api/search_by_provider/#{@test_hierarchy_entry_unpublished.identifier}.json?hierarchy_id=#{@test_hierarchy_entry_unpublished.hierarchy_id}")
    debugger if response.length > 1 # I assume this is because something was changed in memory, but I lost the chance to peek at
                                    # it, so I'm using this to catch it next time.
    response.length.should == 0
  end

  context 'batch mode' do

    let(:hierarchy) { Hierarchy.gen }
    let(:taxon_concept) { TaxonConcept.gen }
    let(:hierarchy_entry1) { HierarchyEntry.gen( hierarchy: hierarchy, identifier: "1", taxon_concept: taxon_concept ) }
    let(:hierarchy_entry2) { HierarchyEntry.gen( hierarchy: hierarchy, identifier: "2", taxon_concept: taxon_concept ) }

    context 'JSON format' do 
      it 'returns all the existing provided identifiers' do 
        response = get_as_json("/api/search_by_provider/#{hierarchy_entry1.identifier}%2C#{hierarchy_entry2.identifier}.json?hierarchy_id=#{hierarchy.id}&batch=true")
        expect(response.length).to eq 2
      end
      
      it "doesn't include the non-existing identifier in the response" do
        response = get_as_json("/api/search_by_provider/#{hierarchy_entry1.identifier}%2CNonExistingIdentifier.json?hierarchy_id=#{hierarchy.id}&batch=true")
        expect(response.length).to eq 1
        expect(response.map(&:keys).flatten).not_to include "NonExistingIdentifier"
      end
    end
    context 'XML format' do 
        it 'returns all the existing provided identifiers' do 
        response = get_as_xml("/api/search_by_provider/#{hierarchy_entry1.identifier}%2C#{hierarchy_entry2.identifier}.xml?hierarchy_id=#{hierarchy.id}&batch=true")
        expect(response.xpath("//page").count).to eq 2

      end
      
      it "doesn't include the non-existing identifier in the response" do
        response = get_as_xml("/api/search_by_provider/#{hierarchy_entry1.identifier}%2CNonExistingIdentifier.xml?hierarchy_id=#{hierarchy.id}&batch=true")
        expect(response.xpath("//page").count).to eq 1
      end
    end
  end
end
