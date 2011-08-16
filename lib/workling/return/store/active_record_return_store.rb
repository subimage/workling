require 'workling/return/store/base'

#
#  Recommended Return Store if you are using the ActiveRecordClient.
#  Simply sets and gets values in the return_store field in the database.
#  'key' is the uid of the job.
#
#  Be careful with this on Rails <~ 2.2, as it probably creates thread-safety
#  issues when setting.
#
module Workling
  module Return
    module Store
      class ActiveRecordReturnStore < Base

        class WorklingJob < ActiveRecord::Base
          serialize :options, Hash
        end

        # set a value in the queue 'key'. 
        def set(key, value)
          namespace = Workling.config[:namespace] || ""
          uid = namespace + ":" + key
          WorklingJob.transaction do
            job = WorklingJob.find(:first, :conditions => {:uid => uid},
              :lock => true)
            if job
              job.return_store = ActiveSupport::JSON.encode(value)
              job.save!
            end
          end
        end

        # get a value from starling queue 'key'.
        def get(key)
          namespace = Workling.config[:namespace] || ""
          uid = namespace + ":" + key
          job = WorklingJob.find(:first, :conditions => {:uid => uid})
          if job && job.return_store
            ActiveSupport::JSON.decode(job.return_store)
          else
            nil
          end
        end
      end
    end
  end
end
