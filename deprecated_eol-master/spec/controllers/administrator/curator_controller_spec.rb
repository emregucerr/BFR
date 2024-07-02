require File.dirname(__FILE__) + '/../../spec_helper'

describe Administrator::CuratorController do
  before(:all) do
    truncate_all_tables
    Language.create_english
    CuratorLevel.create_enumerated
    # create curator community if it doesn't exist
    Community.find_or_create_by_description_and_name($CURATOR_COMMUNITY_DESC, $CURATOR_COMMUNITY_NAME)
    @curator = User.gen(:curator_level => CuratorLevel.full_curator, :credentials => 'Blah', :curator_scope => 'More blah')
    @user_wants_to_be_curator = User.gen(:requested_curator_level_id => CuratorLevel.full_curator.id, :credentials => 'Blah', :curator_scope => 'More blah')
    @admin = User.gen(:username => "admin", :password => "admin")
    @admin.grant_admin
  end

  after(:all) do
    CuratorCommunity.get.destroy
  end

  it "should set @users when accessing GET /index" do
    get :index, nil, { :user_id => @admin.id }
    assigns[:users].should_not be_nil
    assigns[:users].should include(@curator)
    assigns[:users].should include(@user_wants_to_be_curator)
  end

  it "should set @users when accessing GET /index for unapproved curators" do
    get :index, { :only_unapproved => true }, { :user_id => @admin.id }
    assigns[:users].should_not be_nil
    assigns[:users].should_not include(@curator)
    assigns[:users].should include(@user_wants_to_be_curator)
  end

  it "should raise SecurityViolation for non-admin users" do
    expect { get :index, nil, { :user_id => @curator.id } }.
      to raise_error(EOL::Exceptions::SecurityViolation) {|e| e.flash_error_key.should == :administrators_only}
  end
  # # if we allow the rescue_from in ApplicationController for the test ENV, then tests like this will need to be:
  # it "should raise SecurityViolation for non-admin users" do
  #   controller.should_receive(:rescue_from_exception).once.with do |p|
  #     p.should be_an_instance_of(EOL::Exceptions::SecurityViolation)
  #     p.flash_error_key.should == "ASdfasdf"
  #   end
  #   get :index, nil, { :user_id => @curator.id }
  # end
  

end
