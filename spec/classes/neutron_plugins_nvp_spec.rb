require 'spec_helper'

describe 'neutron::plugins::nvp' do

  let :pre_condition do
    "class { 'neutron':
      rabbit_password => 'passw0rd',
      core_plugin     => 'neutron.plugins.nicira.NeutronPlugin.NvpPluginV2' }"
  end

  let :default_params do
    {
        :metadata_mode  => 'access_network',
        :package_ensure => 'present'}
  end

  let :default_facts do
    { :operatingsystem           => 'default',
      :operatingsystemrelease    => 'default'
    }
  end

  let :params do
    {
        :default_tz_uuid => '0344130f-1add-4e86-b36e-ad1c44fe40dc',
        :nvp_controllers => %w(10.0.0.1 10.0.0.2),
        :nvp_user => 'admin',
        :nvp_password => 'password'}
  end

  let :optional_params do
    {:default_l3_gw_service_uuid => '0344130f-1add-4e86-b36e-ad1c44fe40dc'}
  end

  shared_examples_for 'neutron plugin nvp' do
    let :p do
      default_params.merge(params)
    end

    it { is_expected.to contain_class('neutron::params') }

    it 'should have' do
      is_expected.to contain_package('neutron-plugin-nvp').with(
                 :name   => platform_params[:nvp_server_package],
                 :ensure => p[:package_ensure],
                 :tag    => 'openstack'
             )
    end

    it 'should configure neutron.conf' do
      is_expected.to contain_neutron_config('DEFAULT/core_plugin').with_value('neutron.plugins.nicira.NeutronPlugin.NvpPluginV2')
    end

    it 'should create plugin symbolic link' do
      is_expected.to contain_file('/etc/neutron/plugin.ini').with(
        :ensure  => 'link',
        :target  => '/etc/neutron/plugins/nicira/nvp.ini',
        :require => 'Package[neutron-plugin-nvp]'
      )
    end

    it 'should configure nvp.ini' do
      is_expected.to contain_neutron_plugin_nvp('DEFAULT/default_tz_uuid').with_value(p[:default_tz_uuid])
      is_expected.to contain_neutron_plugin_nvp('nvp/metadata_mode').with_value(p[:metadata_mode])
      is_expected.to contain_neutron_plugin_nvp('DEFAULT/nvp_controllers').with_value(p[:nvp_controllers].join(','))
      is_expected.to contain_neutron_plugin_nvp('DEFAULT/nvp_user').with_value(p[:nvp_user])
      is_expected.to contain_neutron_plugin_nvp('DEFAULT/nvp_password').with_value(p[:nvp_password])
      is_expected.to contain_neutron_plugin_nvp('DEFAULT/nvp_password').with_secret( true )
      is_expected.not_to contain_neutron_plugin_nvp('DEFAULT/default_l3_gw_service_uuid').with_value(p[:default_l3_gw_service_uuid])
    end

    context 'configure nvp with optional params' do
      before :each do
        params.merge!(optional_params)
      end

      it 'should configure nvp.ini' do
        is_expected.to contain_neutron_plugin_nvp('DEFAULT/default_l3_gw_service_uuid').with_value(params[:default_l3_gw_service_uuid])
      end
    end

    context 'configure nvp with wrong core_plugin configure' do
      let :pre_condition do
        "class { 'neutron':
          rabbit_password => 'passw0rd',
          core_plugin     => 'foo' }"
      end

      it_raises 'a Puppet::Error', /nvp plugin should be the core_plugin in neutron.conf/
    end
  end

  begin
    context 'on Debian platforms' do
      let :facts do
        default_facts.merge({:osfamily => 'Debian'})
      end

      let :platform_params do
        { :nvp_server_package => 'neutron-plugin-nicira' }
      end

      it_configures 'neutron plugin nvp'
    end

    context 'on RedHat platforms' do
      let :facts do
        default_facts.merge({
          :osfamily               => 'RedHat',
          :operatingsystemrelease => '7'
        })
      end

      let :platform_params do
        { :nvp_server_package => 'openstack-neutron-nicira' }
      end

      it_configures 'neutron plugin nvp'
    end
  end

end
