require 'workling/clients/base'

#
#  This client can be used to store the queue in an ActiveRecord database.
#
module Workling
  module Clients
    class ActiveRecordClient < Workling::Clients::Base

      class WorklingJob < ActiveRecord::Base
        serialize :options, Hash
      end

      def connect
        # nop
        true
      end

      def close
        # nop
      end

      def complete(uid, error=nil)
        namespace = Workling.config[:namespace] || ""
        uid = namespace + ":" + uid
        WorklingJob.transaction do
          job = WorklingJob.find(:first, :conditions => {:uid => uid},
            :lock => true)
          if job
            job.status = "processed"
            job.finished_at = Time.now
            if error
              status = Thread.current[:status]
              job.error = true
              job.error_message = error.message
              job.error_backtrace = error.backtrace
            end
            job.save!
            job.options
          end
        end
      end

      # implements the client job request and retrieval
      def request(key, value)
        namespace = Workling.config[:namespace] || ""
        key = namespace + ":" + key
        uid = (value && value.is_a?(Hash) ? value[:uid] : nil)
        uid = namespace + ":" + uid if uid
        WorklingJob.create({:queue => key, :options => value, :uid => uid})
      end

      def retrieve(key)
        namespace = Workling.config[:namespace] || ""
        key = namespace + ":" + key
        job = ActiveRecord::Base.silence do
          WorklingJob.find(:first,
            :conditions => ["queue = ? AND status IS NULL", key])
        end

        # Need to use update_all and check return value to avoid deadlock
        if job
          count = WorklingJob.update_all ["status = ?", "processing"], ["id = ?", job.id]

          if count == 1
            status = Thread.current[:status]
            job.status = "processing"
            job.started_at = Time.now
            job.worker_name = status.worker_name
            job.save!
            job.options
          else
            nil
          end
        end
      end
    end
  end
end

