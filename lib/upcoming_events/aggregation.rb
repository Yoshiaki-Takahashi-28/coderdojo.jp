module UpcomingEvents
  class Aggregation
    def initialize(args)
      @from = Time.zone.today
      @to = @from + 2.months
      @provider = args[:provider]
      # NOTE: 対象は一旦収集可能な connpass, doorkeeper のみにする
      @externals = fetch_dojos(@provider)
    end

    def run
      puts "UpcomingEvents aggregate"
      with_notifying do
        delete_upcoming_events
        execute
      end
    end

    private

    def fetch_dojos(provider)
      base_providers = DojoEventService::EXTERNAL_SERVICES - [:facebook]
      services = if provider.blank?
                   # 全プロバイダ対象
                   base_providers
                 elsif base_providers.include?(provider.to_sym)
                   [provider.to_sym]
                 end
      return [] unless services
      find_dojos_by(services)
    end

    def find_dojos_by(services)
      services.each.with_object({}) do |name, hash|
        hash[name] = Dojo.eager_load(:dojo_event_services).where(dojo_event_services: { name: name }).to_a
      end
    end

    def with_notifying
      yield
      Notifier.notify_success(@provider)
    rescue => e
      Notifier.notify_failure(@provider, e)
    end

    def delete_upcoming_events
      UpcomingEvent.until(@from).delete_all
    end

    def execute
      target_period = @from..@to
      @externals.each do |kind, list|
        puts "Aggregate of #{kind}"
        "UpcomingEvents::Tasks::#{kind.to_s.camelize}".constantize.new(list, target_period).run
      end
    end

    class Notifier
      class << self
        def notify_success(provider)
          notify("近日開催イベント情報#{provider_info(provider)}を収集しました")
        end

        def notify_failure(provider, exception)
          notify("近日開催イベント情報の収集#{provider_info(provider)}でエラーが発生しました\n#{exception.message}\n#{exception.backtrace.join("\n")}")
        end

        private

        def provider_info(provider)
          provider ? "(#{provider})" : nil
        end

        def idobata_hook_url
          return @idobata_hook_url if defined?(@idobata_hook_url)
          @idobata_hook_url = ENV['IDOBATA_HOOK_URL']
        end

        def notifierable?
          idobata_hook_url.present?
        end

        def notify(msg)
          $stdout.puts msg
          puts `curl --data-urlencode "source=#{msg}" -s #{idobata_hook_url} -o /dev/null -w "idobata: %{http_code}"` if notifierable?
        end
      end
    end
  end
end