require 'logger'
require_relative '../spec_helper'

describe AdminUI::Operation, :type => :integration do
  include CCHelper
  include NATSHelper
  include VARZHelper
  include OperationHelper

  let(:data_file) { '/tmp/admin_ui_data.json' }
  let(:log_file) { '/tmp/admin_ui.log' }
  let(:logger) { Logger.new(log_file) }
  let(:config) do
    AdminUI::Config.load(:cloud_controller_discovery_interval => 1,
                         :cloud_controller_uri                => 'http://api.cloudfoundry',
                         :data_file                           => data_file,
                         :monitored_components                => [],
                         :uaa_admin_credentials               => { :username => 'user', :password => 'password' })
  end
  let(:client) { AdminUI::RestClient.new(config, logger) }

  before do
    AdminUI::Config.any_instance.stub(:validate)
    cc_stub(config)
    nats_stub
    varz_stub
    operation_stub(config)
  end

  let(:cc) { AdminUI::CC.new(config, logger, client) }
  let(:email) { AdminUI::EMail.new(config, logger) }
  let(:nats) { AdminUI::NATS.new(config, logger, email) }
  let(:varz) { AdminUI::VARZ.new(config, logger, nats) }
  let(:operation) { AdminUI::Operation.new(config, logger, cc, client, varz) }

  after do
    Process.wait(Process.spawn({}, "rm -fr #{ log_file }"))
  end

  context 'Stubbed HTTP' do
    context 'manage application' do
      it 'stops the running application' do
        expect { operation.manage_application('STOP', 'test_org', 'test_space', 'test') }.to change { cc.applications['items'][0]['state'] }.from('STARTED').to('STOPPED')
      end

      it 'starts the stopped application' do
        operation.manage_application('STOP', 'test_org', 'test_space', 'test')
        expect { operation.manage_application('START', 'test_org', 'test_space', 'test') }.to change { cc.applications['items'][0]['state'] }.from('STOPPED').to('STARTED')
      end

      it 'restarts the application' do
        operation.manage_application('RESTART', 'test_org', 'test_space', 'test')
        expect(cc.applications['items'][0]['state']).to eq('STARTED')
      end
    end
  end

  context 'manage route' do
    it 'deletes specific route' do
      expect { operation.manage_route('DELETE', 'test_host.test_domain') }.to change { cc.routes['items'].length }.from(1).to(0)
    end
  end
end
