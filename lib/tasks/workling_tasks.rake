namespace :db do
  namespace :migrate do
    description = "Migrate the database through scripts in vendor/plugins/workling/lib/db/migrate"
    description << "and update db/schema.rb by invoking db:schema:dump."
    description << "Target specific version with VERSION=x. Turn off output with VERBOSE=false."
 
    desc description
    task :workling => :environment do
      ActiveRecord::Migration.verbose = ENV["VERBOSE"] ? ENV["VERBOSE"] == "true" : true
      ActiveRecord::Migrator.migrate("vendor/plugins/workling/lib/db/migrate/", ENV["VERSION"] ? ENV["VERSION"].to_i : nil)
      Rake::Task["db:schema:dump"].invoke if ActiveRecord::Base.schema_format == :ruby
    end
    
    namespace :workling do
      description = "Rollback the database through scripts in vendor/plugins/workling/lib/db/migrate"
      description << "and update db/schema.rb by invoking db:schema:dump. Turn off output with VERBOSE=false."
      
      desc description
      task :down => :environment do
        ActiveRecord::Migration.verbose = ENV["VERBOSE"] ? ENV["VERBOSE"] == "true" : true
        ActiveRecord::Migrator.rollback("vendor/plugins/workling/lib/db/migrate/")
        Rake::Task["db:schema:dump"].invoke if ActiveRecord::Base.schema_format == :ruby
      end
    end
  end
end
