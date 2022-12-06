require 'cocoapods-meitu-bin/native/sources_manager'
require 'cocoapods-meitu-bin/command/bin/repo/update'
require 'cocoapods-meitu-bin/config/config'
require 'cocoapods/user_interface'
require 'yaml'

Pod::HooksManager.register('cocoapods-meitu-bin', :pre_install) do |_context, _|
  require 'cocoapods-meitu-bin/native'
  require 'cocoapods-meitu-bin/helpers/buildAll/bin_helper'

  Pod::UI.puts "当前configuration: `#{ENV['configuration'] || Pod::Config.instance.podfile.configuration}`".green

  # pod bin repo update 更新二进制私有源
  Pod::Command::Bin::Repo::Update.new(CLAide::ARGV.new($ARGV)).run

  # 有插件/本地库 且是dev环境下，默认进入源码白名单  过滤 archive命令
  if _context.podfile.plugins.keys.include?('cocoapods-meitu-bin') && _context.podfile.configuration_env == 'dev'
    dependencies = _context.podfile.dependencies
    dependencies.each do |d|
      next unless d.respond_to?(:external_source) &&
                  d.external_source.is_a?(Hash) &&
                  !d.external_source[:path].nil? &&
                  $ARGV[1] != 'archive'
      _context.podfile.set_use_source_pods d.name
    end
  end

  # 同步 BinPodfile 文件
  project_root = Pod::Config.instance.project_root
  path = File.join(project_root.to_s, 'BinPodfile')

  next unless File.exist?(path)

  contents = File.open(path, 'r:utf-8', &:read)
  podfile = Pod::Config.instance.podfile
  podfile.instance_eval do
    begin
      eval(contents, nil, path)
    rescue Exception => e
      message = "Invalid `#{path}` file: #{e.message}"
      raise Pod::DSLError.new(message, path, e, contents)
    end
  end
end

Pod::HooksManager.register('cocoapods-meitu-bin', :source_provider) do |context, _|
  sources_manager = Pod::Config.instance.sources_manager
  podfile = Pod::Config.instance.podfile
  if podfile
    # 读取配置文件
    config_file = File.join(Pod::Config.instance.project_root, 'BinConfig.yaml')
    if File.exist?(config_file)
      config = YAML.load(File.open(config_file))
      unless config.nil?
        build_config = config['install_config'] || {}
        use_binary = build_config['use_binary'] || false
        podfile.use_binaries!(use_binary) if use_binary
      end
    end
    # 添加源码私有源 && 二进制私有源
    added_sources = sources_manager.code_source_list
    # if podfile.use_binaries? || podfile.use_binaries_selector
    #   added_sources << sources_manager.binary_source
    #   added_sources.reverse!
    # end
    added_sources.each { |source| context.add_source(source)}
  end
end
