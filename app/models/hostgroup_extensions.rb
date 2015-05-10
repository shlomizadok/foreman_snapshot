require 'timeout'
module HostgroupExtensions
  extend ActiveSupport::Concern

  module ClassMethods 
    def snapshot!(host_hash)
      image = nil

      # This could be run from Dynflow or directly, so we need
      # to use uncached{} to be able to detect the change in build state
      begin
        Timeout::timeout(600) do
          if @host = ::Host::Managed.create!(host_hash)
            until @host.build == false
              logger.debug "Sleeping for host build state: #{@host.build}"
              sleep(2)
              # Reload cache for next sleep check
              @host = uncached { Host.find(@host.id) }
            end
          end
          logger.debug "Done waiting - #{@host.build}"
          image = @host.snapshot!
          raise unless @host.destroy
        end
      rescue Timeout::Error => error
        Rails.logger.debug "Could not complete building the host within time"
        raise error
      rescue Exception => error
        Rails.logger.debug error.message
        raise error
      end

      image
    end
  end

end
