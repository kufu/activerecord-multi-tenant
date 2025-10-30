# frozen_string_literal: true

require 'sidekiq/transaction_aware_client'

module MultiTenant
  module SidekiqTransactionAwareClient
    if Sidekiq.gem_version < Gem::Version.new('8.0.0')
      def push(item)
        # 6160 we can't support both Sidekiq::Batch and transactions.
        return @redis_client.push(item) if batching?

        # pre-allocate the JID so we can return it immediately and
        # save it to the database as part of the transaction.
        item['jid'] ||= SecureRandom.hex(12)
        current_tenant = MultiTenant.current_tenant
        AfterCommitEverywhere.after_commit do
          MultiTenant.with(current_tenant) do
            @redis_client.push(item)
          end
        end
        item['jid']
      end
    else
      def push(item)
        # 6160 we can't support both Sidekiq::Batch and transactions.
        return @redis_client.push(item) if batching?

        # pre-allocate the JID so we can return it immediately and
        # save it to the database as part of the transaction.
        item['jid'] ||= SecureRandom.hex(12)
        current_tenant = MultiTenant.current_tenant
        @transaction_backend.call do
          MultiTenant.with(current_tenant) do
            @redis_client.push(item)
          end
        end
        item['jid']
      end
    end
  end
end

if defined?(Sidekiq::TransactionAwareClient)
  Sidekiq::TransactionAwareClient.prepend(MultiTenant::SidekiqTransactionAwareClient)
end
