#
#  Discovery is responsible for loading workers in app/workers. 
#
module Workling
  class Discovery
    cattr_accessor :discovered
    @@discovered = []
    @@queues = ENV['QUEUE'].try(:split, ",")
    
    # requires worklings so that they are added to routing. 
    def self.discover!
      Dir.glob(Workling.load_path.map { |p| "#{ p }/**/*.rb" }).each do |wling|
        name = File.basename(wling, ".rb")
        if !@@queues || @@queues.include?(name.camelize)
          require wling
        end
      end
    end
  end
end
