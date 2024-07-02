require "spec_helper"

describe StaticEolAssetHost do
  
  before(:each) do
    @asset_host = StaticEolAssetHost.asset_host_proc
    @asset_host.should_not be_nil
  end
  
  it "should use static1 for CSS assets" do
    css = "/assets/test.css?1230601161"
    @asset_host.call(css).should =~ /static1\./
  end
  
  it "should use static2 for JS assets" do
    js = "/js/test.js?1230601161"
    @asset_host.call(js).should =~ /static2\./
  end
  
  it "should use use neither static1 nor static2 for image assets" do
    png = "/assets/test.png?1230601161"
    @asset_host.call(png).should_not =~ /static1\./
    @asset_host.call(png).should_not =~ /static2\./
  end

end
