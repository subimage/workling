class CreateWorklingJobs < ActiveRecord::Migration
  def self.up
    create_table :workling_jobs, :force => true do |t|
      t.string  :queue
      t.string  :uid
      t.text    :options
      t.string  :status
      t.string  :worker_name
      t.boolean :error
      t.text    :error_message
      t.text    :error_backtrace
      t.text    :return_store
      t.timestamps
    end

    add_index :workling_jobs, [:queue, :status]
    add_index :workling_jobs, :uid
  end

  def self.down
    drop_table :workling_jobs
  end
end

