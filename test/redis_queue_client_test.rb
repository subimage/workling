require File.dirname(__FILE__) + '/test_helper'

context "The redis queue client" do 
  setup do
    Redis.stubs(:new).returns(mock())
  end
  
  specify "should load it's config as well as any given Redis options from RAILS_ENV/config/workling.yml" do
    Workling.send :class_variable_set, "@@config", { :listens_on => "localhost:6739", :redis_options => { :namespace => "myapp_dev" } }
    client = Workling::Clients::RedisQueueClient.new
    client.connect
    
    client.server_url[0].should == 'localhost'
    client.server_url[1].should == '6739'
    client.key_namespace.should.equal "myapp_dev"
  end
  
  
  specify "should load it's config correctly if no redis options are given" do
    Workling.send :class_variable_set, "@@config", { :listens_on => "localhost:6739" }
    client = Workling::Clients::RedisQueueClient.new
    client.connect

    client.server_url[0].should == 'localhost'
    client.server_url[1].should == '6739'
    client.key_namespace.should.equal ''
  end  
end