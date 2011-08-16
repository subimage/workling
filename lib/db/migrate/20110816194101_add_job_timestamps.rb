class AddJobTimestamps < ActiveRecord::Migration
  def self.up
    add_column :workling_jobs, :started_at, :datetime
    add_column :workling_jobs, :finished_at, :datetime
  end

  def self.down
    remove_column :workling_jobs, :started_at
    remove_column :workling_jobs, :finished_at
  end
end

