require File.dirname(__FILE__) + '/test_helper.rb'

context "the redis runner" do
  specify "should set up a redis client" do
    Workling::Remote.dispatcher = Workling::Remote::Runners::RedisRunner.new
    Workling::Remote.dispatcher.client.should.not.equal nil
  end
end