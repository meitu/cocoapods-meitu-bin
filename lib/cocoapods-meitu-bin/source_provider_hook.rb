require 'cocoapods-meitu-bin/native/sources_manager'
require 'cocoapods-meitu-bin/command/bin/repo/update'
require 'cocoapods-meitu-bin/config/config'
require 'cocoapods/user_interface'
require 'yaml'
require 'cocoapods'

#获取服务端podfile.lock文件
def get_podfile_lock
  begin
    # 默认是获取要获取服务端podfile.lock文件
    is_load_podfile_lock = true
    # MEITU_LOAD_CACHE_PODFILE_LOCK 为false时不获取服务端podfile.lock文件
    if ENV['MEITU_LOAD_CACHE_PODFILE_LOCK'] && ENV['MEITU_LOAD_CACHE_PODFILE_LOCK'] == 'false'
      is_load_podfile_lock = false
    end
    # 判断是否有update参数 时不获取服务端podfile.lock文件
    ARGV.each do |arg|
      if arg == 'update'
        is_load_podfile_lock = false
      end
    end
    # podfile.lock文件下载和使用逻辑
    if is_load_podfile_lock
      #获取 PODFILE CHECKSUM 用来判断服务端是否存在该podfile.lock
      checksum = Pod::Config.instance.podfile.checksum
      puts checksum
      # zip下载地址
      curl = "https://xiuxiu-dl-meitu-com.obs.cn-north-4.myhuaweicloud.com/ios/binary/MTXX/#{checksum}/podfile.lock.zip"
      # 判断zip文件是否存在 存在下载并解压
      if system("curl -o /dev/null -s -w %{http_code} #{curl} | grep 200")
        puts "获取服务端存储的podfile.lcok文件".green
        #下载并解压的podfile.zip文件
        if system("curl -O #{curl}") && system("unzip -o podfile.lock.zip")
          Pod::UI.puts "下载并解压podfile.lcok文件成功".green
          `rm -rf podfile.lock.zip`
          # 设置获取到的podfile.lock对象
          PodUpdateConfig.set_lockfile( Pod::Config.instance.installation_root + 'Podfile.lock')
          #获取analyzer
          analyzer = Pod::Installer::Analyzer.new(
            Pod::Config.instance.sandbox,
            Pod::Config.instance.podfile,
            PodUpdateConfig.lockfile
          )
          analyzer.analyze(true)

          #获取analyzer中所有git 且branch 指向的pod
          Pod::Config.instance.podfile.dependencies.map do |dependency|
            if dependency.external_source && dependency.external_source[:git] && (dependency.external_source[:branch] || (dependency.external_source.size == 1))
              #brash 指定的组件添加到全局PodUpdateConfig配置中，执行pod install 需要更新的分支最新提交
              PodUpdateConfig.add_value(dependency.name)
            end
          end
        else
          puts "获取podfile.lcok文件失败"
          `rm -rf podfile.lock.zip`
        end
      end
    end
  rescue => error
    puts error
    puts "podfile.lcok相关发生异常"
    `rm -rf podfile.lock.zip`
    `rm -rf podfile.lock`
  end
end

# 上传podfile.lock文件到服务端
def upload_podfile_lock
  begin
    checksum = Pod::Config.instance.podfile.checksum
    curl = "https://xiuxiu-dl-meitu-com.obs.cn-north-4.myhuaweicloud.com/ios/binary/MTXX/#{checksum}/podfile.lock.zip"
    # 服务端不存在该podfiel.lock文件才上传，避免频繁上报同一个文件
    if !system("curl -o /dev/null -s -w %{http_code} #{curl} | grep 200")
      Pod::UI.puts "上报podfile.lcok文件到服务端".green
      puts checksum
      if system("zip  podfile.lock.zip Podfile.lock") && system("curl -F \"name=MTXX\" -F \"version=#{checksum}\" -F \"file=@#{Pathname.pwd}/podfile.lock.zip\" http://nezha.community.cloud.meitu.com/file/upload.json")
        Pod::UI.puts "上报podfile.lcok文件到服务端成功".green
        `rm -rf podfile.lock.zip`
      else
        Pod::UI.puts "上报podfile.lcok文件到服务端失败".red
        `rm -rf podfile.lock.zip`
      end
    end

  rescue => error
     puts "上传podfile.lcok文件失败".red
    `rm -rf podfile.zip`
  end
end

Pod::HooksManager.register('cocoapods-meitu-bin', :pre_install) do |_context|
  require 'cocoapods-meitu-bin/native'
  require 'cocoapods-meitu-bin/helpers/buildAll/bin_helper'

  Pod::UI.puts "当前configuration: `#{ENV['configuration'] || Pod::Config.instance.podfile.configuration}`".green
  # checksum = Pod::Config.instance.podfile.checksum
  # puts Pod::Config.instance
  # installer =  Installer.new(config.sandbox, config.podfile, config.lockfile)
  # puts checksum
  get_podfile_lock






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

# 注册 pod install 钩子
Pod::HooksManager.register('cocoapods-meitu-bin', :post_install) do |context|
  # p "hello world!  post_install"
  upload_podfile_lock

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
