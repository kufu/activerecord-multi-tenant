# frozen_string_literal: true

require 'spec_helper'
require 'sidekiq/client'
require 'sidekiq/testing'
require 'activerecord-multi-tenant/sidekiq'

describe MultiTenant, 'SidekiqTransactionAwareClient' do
  describe 'transactional_push' do
    def transactional_push
      allow(Sidekiq).to receive(:default_job_options).and_return(Sidekiq.default_job_options.dup)
      stub_const('Sidekiq::JobUtil::TRANSIENT_ATTRIBUTES', Sidekiq::JobUtil::TRANSIENT_ATTRIBUTES.dup)

      Sidekiq.transactional_push!
    end

    it 'sets the multitenant context when the tenant is switched within a transaction' do
      transactional_push

      worker = Class.new { include Sidekiq::Worker }
      stub_const('TestWorker', worker)

      account = Account.create!(name: 'foo')
      other_account = Account.create!(name: 'bar')

      MultiTenant.with(account) do
        Account.transaction do
          MultiTenant.with(other_account) do
            TestWorker.perform_async
          end
        end
      end

      expect(TestWorker.jobs[-1]['multi_tenant']).to eq(
        {
          'class' => 'Account',
          'id' => other_account.id
        }
      )
    end

    it 'does not set the multitenant context when the tenant is switched to none within a transaction' do
      transactional_push

      worker = Class.new { include Sidekiq::Worker }
      stub_const('TestWorker', worker)

      account = Account.create!(name: 'foo')

      MultiTenant.with(account) do
        Account.transaction do
          MultiTenant.without do
            TestWorker.perform_async
          end
        end
      end

      expect(TestWorker.jobs[-1]).to_not be_key('multi_tenant')
    end

    if Gem::Version.new('7.3.0') <= Sidekiq.gem_version && Sidekiq.gem_version < Gem::Version.new('8.0.0')
      it 'Sidekiq gem has not changed' do
        meth = Sidekiq::TransactionAwareClient.instance_method(:push)

        lib_re = %r{lib/sidekiq/transaction_aware_client\.rb}
        meth = meth.super_method while meth && !meth.source_location[0].match?(lib_re)

        expect(meth.source.strip_heredoc).to eq(<<~CODE), -> { 'Need to check for changes' }
          def push(item)
            # 6160 we can't support both Sidekiq::Batch and transactions.
            return @redis_client.push(item) if batching?

            # pre-allocate the JID so we can return it immediately and
            # save it to the database as part of the transaction.
            item["jid"] ||= SecureRandom.hex(12)
            AfterCommitEverywhere.after_commit { @redis_client.push(item) }
            item["jid"]
          end
        CODE
      end
    end

    if Gem::Version.new('8.0.0') <= Sidekiq.gem_version && Sidekiq.gem_version < Gem::Version.new('9.0.0')
      it 'Sidekiq gem has not changed' do
        meth = Sidekiq::TransactionAwareClient.instance_method(:push)

        lib_re = %r{lib/sidekiq/transaction_aware_client\.rb}
        meth = meth.super_method while meth && !meth.source_location[0].match?(lib_re)

        expect(meth.source.strip_heredoc).to eq(<<~CODE), -> { 'Need to check for changes' }
          def push(item)
            # 6160 we can't support both Sidekiq::Batch and transactions.
            return @redis_client.push(item) if batching?

            # pre-allocate the JID so we can return it immediately and
            # save it to the database as part of the transaction.
            item["jid"] ||= SecureRandom.hex(12)
            @transaction_backend.call { @redis_client.push(item) }
            item["jid"]
          end
        CODE
      end
    end
  end
end
