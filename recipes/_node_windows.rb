#
# Cookbook Name:: jenkins
# Recipe:: _node_windows
#
# Author:: Doug MacEachern <dougm@vmware.com>
# Author:: Fletcher Nichol <fnichol@nichol.ca>
#
# Copyright 2010, VMware, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

home_dir = node['jenkins']['node']['home']
server_url = node['jenkins']['server']['url']

jenkins_exe = "#{home_dir}\\jenkins-slave.exe"
service_name = "jenkinsslave"
auth_enabled = node['jenkins']['node']['auth_enabled']
auth_ad_domain = node['jenkins']['node']['auth_ad_domain']
auth_user = node['jenkins']['node']['auth_user']
auth_password = node['jenkins']['node']['auth_password']
interactive_enabled = node['jenkins']['node']['interactive_enabled']

if auth_enabled
  directory home_dir do
    action :create
    inherits true
    recursive true
    rights :full_control, "#{auth_ad_domain}\\#{auth_user}"
  end
else
  directory home_dir do
    action :create
  end
end

env "JENKINS_HOME" do
  action :create
  value home_dir
end

env "JENKINS_URL" do
  action :create
  value server_url
end

remote_file "#{home_dir}\\slave.jar" do
  source "#{server_url}/jnlpJars/slave.jar"
  notifies :restart, "service[#{service_name}]", :immediately
end

cookbook_file "#{node[:jenkins][:node][:home]}/node_info.groovy" do
  source "node_info.groovy"
end


template "#{home_dir}/jenkins-slave.xml" do
  source "jenkins-slave.xml.erb"
  variables(:auth_enabled => auth_enabled,
            :auth_user => auth_user,
            :auth_password => auth_password,
            :interactive_enabled => interactive_enabled,
            :jenkins_home => home_dir,
            :jnlp_url => "#{server_url}/computer/#{node['jenkins']['node']['name']}/slave-agent.jnlp",
            :jnlp_secret => secret)
  notifies :restart, "service[#{service_name}]"
end

remote_file jenkins_exe do
  source "http://download.java.net/maven/2/com/sun/winsw/winsw/1.8/winsw-1.8-bin.exe"
  not_if { File.exists?(jenkins_exe) }
end

execute "#{jenkins_exe} install" do
  cwd home_dir
  only_if { WMI::Win32_Service.find(:first, :conditions => {:name => service_name}).nil? }
end

execute "config_jenkins_service_user" do
  command "sc.exe config \"#{service_name}\" obj= \"#{auth_ad_domain}\\#{auth_user}\" password= \"#{auth_password}\""
  only_if { WMI::Win32_Service.find(:first, :conditions => {:name => service_name, :user => auth_user}).nil? && auth_enabled }
  notifies :restart, "service[#{service_name}]", :delayed
end

jenkins_node node['jenkins']['node']['name'] do
  description  node['jenkins']['node']['description']
  executors    node['jenkins']['node']['executors']
  remote_fs    node['jenkins']['node']['home']
  labels       node['jenkins']['node']['labels']
  mode         node['jenkins']['node']['mode']
  launcher     node['jenkins']['node']['launcher']
  mode         node['jenkins']['node']['mode']
  availability node['jenkins']['node']['availability']
  auth_enabled node['jenkins']['node']['auth_enabled']
  auth_user    node['jenkins']['node']['auth_user']
  auth_password node['jenkins']['node']['auth_password']
end

secret = ''
jenkins_cli "node_info for #{node['jenkins']['node']['name']} to get jnlp secret" do
  command "groovy node_info.groovy #{node['jenkins']['node']['name']}"
  block do |stdout|
    current_node = JSON.parse( stdout )
    secret.replace current_node['secret'] if current_node['secret']
  end
end

service service_name do
  action :start
end
