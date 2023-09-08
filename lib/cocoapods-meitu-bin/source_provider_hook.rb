require 'cocoapods-meitu-bin/native/sources_manager'
require 'cocoapods-meitu-bin/command/bin/repo/update'
require 'cocoapods-meitu-bin/config/config'
require 'cocoapods/user_interface'
require 'digest'
require 'yaml'
require 'cocoapods'
require 'json'
require 'net/http'
#获取服务端podfile.lock文件
def get_podfile_lock
  begin
    # 默认是获取要获取服务端podfile.lock文件
    is_load_podfile_lock = true
    #获取 PODFILE CHECKSUM 用来判断服务端是否存在该podfile.lock
    checksum = get_checksum(Pod::Config.instance.podfile_path)
    PodUpdateConfig.set_checksum(checksum)
    #目前只支持MTXX target "MTXX" 项目 #想要支持其他项目可以添加对应 target "xxx"
    content = File.read(Pod::Config.instance.podfile_path)
    if content
      if content.include?("target \"MTXX\"")
        is_load_podfile_lock = true
        PodUpdateConfig.set_is_mtxx(true)
      else
        is_load_podfile_lock = false
        PodUpdateConfig.set_is_mtxx(false)
      end
    end
    # MEITU_LOAD_CACHE_PODFILE_LOCK 为false时不获取服务端podfile.lock文件
    if ENV['MEITU_LOAD_CACHE_PODFILE_LOCK'] && ENV['MEITU_LOAD_CACHE_PODFILE_LOCK'] == 'false'
      is_load_podfile_lock = false
    end
    # 判断是否有update参数 时不获取服务端podfile.lock文件
    ARGV.each do |arg|
      if arg == 'update' || arg == '--no-cloud'
        is_load_podfile_lock = false
      end
    end
    # podfile.lock文件下载和使用逻辑
    if is_load_podfile_lock
      Pod::UI.puts "当前podfile文件的checksum:#{checksum}".green
      # zip下载地址
      curl = "https://xiuxiu-dl-meitu-com.obs.cn-north-4.myhuaweicloud.com/ios/binary/MTXX/#{checksum}/podfile.lock.zip"
      # 判断服务端是否存在该podfile.lock
      is_load_podfile_lock = false
      if system("curl -o /dev/null -s -w %{http_code} #{curl} | grep 200  > /dev/null 2>&1")
        Pod::UI.puts "匹配到精准podfile.lock文件，使用当前podfile文件的checksum:#{checksum}获取对应的podfile.lock文件".green
        is_load_podfile_lock = true
      end

      if !is_load_podfile_lock
        branch_value = get_branch_name
        curl = "https://xiuxiu-dl-meitu-com.obs.cn-north-4.myhuaweicloud.com/ios/binary/MTXX/#{branch_value}/podfile.lock.zip"
        if system("curl -o /dev/null -s -w %{http_code} #{curl} | grep 200  > /dev/null 2>&1")
          Pod::UI.puts "无法匹配到精准podfile.lock文件，使用当前分支：#{branch_value} 对应的podfile.lock文件".green
          is_load_podfile_lock = true
        end
        #兜底使用develop的podfile.lock
        if !is_load_podfile_lock
          Pod::UI.puts "服务端不存在该podfile.lock文件，使用develop分支的podfile.lock文件兜底".green
          curl = "https://xiuxiu-dl-meitu-com.obs.cn-north-4.myhuaweicloud.com/ios/binary/MTXX/develop/podfile.lock.zip"
          is_load_podfile_lock = true
        end
      end
      # 判断是否需要下载podfile.lock文件
      if is_load_podfile_lock
        Pod::UI.puts "获取服务端存储的podfile.lcok文件".green
        #下载并解压的podfile.zip文件
        if system("curl -O #{curl} > /dev/null 2>&1") && system("unzip -o podfile.lock.zip  > /dev/null 2>&1")
          Pod::UI.puts "下载并解压podfile.lcok文件成功".green
          `rm -rf podfile.lock.zip`
          # 设置获取到的podfile.lock对象
          PodUpdateConfig.set_lockfile(Pod::Config.instance.installation_root + 'Podfile.lock')
          #获取analyzer
          Pod::UI.puts "提前根据checksum命中podfile.lcok进行依赖分析".green
          analyzer = Pod::Installer::Analyzer.new(
            Pod::Config.instance.sandbox,
            Pod::Config.instance.podfile,
            PodUpdateConfig.lockfile
          )
          analyzer.update_repositories
          PodUpdateConfig.set_repo_update
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
    puts "podfile.lcok相关处理发生异常，报错原因：#{error}"
    PodUpdateConfig.clear
    `rm -rf podfile.lock.zip`
    `rm -rf podfile.lock`
  end
end


# 上传podfile.lock文件到服务端
def upload_podfile_lock(checksum,upload = false)
  begin
    curl = "https://xiuxiu-dl-meitu-com.obs.cn-north-4.myhuaweicloud.com/ios/binary/MTXX/#{checksum}/podfile.lock.zip"
    # 服务端不存在该podfiel.lock文件才上传，避免频繁上报同一个文件
    if  upload || !system("curl -o /dev/null -s -w %{http_code} #{curl} | grep 200 > /dev/null 2>&1")
      Pod::UI.puts "根据checksum:#{checksum}上报podfile.lcok文件到服务端".green
      if upload
        puts "mbox工作目录/mtxx/MTXX/podfile 对应的checksum = #{checksum}"
      end
      if system("zip  podfile.lock.zip Podfile.lock > /dev/null 2>&1") && system("curl -F \"name=MTXX\" -F \"version=#{checksum}\" -F \"file=@#{Pathname.pwd}/podfile.lock.zip\" http://nezha.community.cloud.meitu.com/file/upload.json > /dev/null 2>&1")
        Pod::UI.puts "上报podfile.lcok文件到服务端成功".green
        `rm -rf podfile.lock.zip`
      else
        Pod::UI.puts "上报podfile.lcok文件到服务端失败".red
        `rm -rf podfile.lock.zip`
      end
    end
  rescue => error
     puts "上传podfile.lcok文件失败，失败原因：#{error}"
    `rm -rf podfile.zip`
  end
end
def upload_mbox_podfile_lock
  begin
    podfile_path = Pod::Config.instance.installation_root + 'mtxx/MTXX' + 'Podfile'
    checksum = get_checksum(podfile_path)
    if checksum && checksum.is_a?(String) && checksum.length > 0
      upload_podfile_lock(checksum,true )
    end
  rescue => error
    puts "mbox podfile.lcok文件兼容处理失败,失败原因：#{error}"
  end
end
def upload_branch_podfile_lock
  begin
    branch_value = get_branch_name
    if branch_value && branch_value.is_a?(String) && branch_value.length > 0
      if system("zip  podfile.lock.zip Podfile.lock > /dev/null 2>&1") && system("curl -F \"name=MTXX\" -F \"version=#{branch_value}\" -F \"file=@#{Pathname.pwd}/podfile.lock.zip\" http://nezha.community.cloud.meitu.com/file/upload.json > /dev/null 2>&1")
        Pod::UI.puts "根据开发分支名：#{branch_value}上报podfile.lcok文件到服务端成功".green
        `rm -rf podfile.lock.zip`
      else
        Pod::UI.puts "根据开发分支名：#{branch_value}上报podfile.lcok文件到服务端失败".red
        `rm -rf podfile.lock.zip`
      end
    end
  rescue => error

  end
end
def get_branch_name
  branch_value = ENV['branch']
  if !branch_value
    mtxx_path = Pod::Config.instance.installation_root + 'mtxx/MTXX'
    #判读podfile文件是否存在
    if  File.exist?(mtxx_path)
      Dir.chdir(mtxx_path) do
        branch_value = `git symbolic-ref --short -q HEAD`
        if branch_value == 'develop'
          branch_value = ""
        end
      end
    else
      branch_value = `git symbolic-ref --short -q HEAD`
    end
  end
  branch_value = branch_value.gsub("\n", "")
  branch_value
end
#过滤出来podfile中实际有效每行内容，拼接成字符串在SHA1 后UTF-8编码下 用来当做依赖缓存文件的key
def get_checksum(file_path)
  return nil unless File.exist?(file_path)
  content = ""
  lines = []
  #过滤出实际使用pod
  File.open(file_path, 'r') do |file|
    file.each_line do |line|
      new_line = line.strip
      if new_line.start_with?("pod")
        lines << new_line
      end
    end
  end
  #给获取的pod list 排序，排除因组件顺序调整导致获取SHA1值不一样
  lines = lines.sort
  lines.each do |line|
    content << line
  end
  checksum = Digest::SHA1.hexdigest(content)
  checksum = checksum.encode('UTF-8') if checksum.respond_to?(:encode)
  return checksum
end

Pod::HooksManager.register('cocoapods-meitu-bin', :pre_install) do |_context|
  start_time = Time.now
  require 'cocoapods-meitu-bin/native'
  require 'cocoapods-meitu-bin/helpers/buildAll/bin_helper'
  Pod::UI.puts "当前configuration: `#{ENV['configuration'] || Pod::Config.instance.podfile.configuration}`".green
  # checksum = Pod::Config.instance.podfile.checksum
  # puts Pod::Config.instance
  # installer =  Installer.new(config.sandbox, config.podfile, config.lockfile)
  # puts checksum
  # pod bin repo update 更新二进制私有源
  Pod::Command::Bin::Repo::Update.new(CLAide::ARGV.new($ARGV)).run

  get_podfile_lock

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
  PodUpdateConfig.set_prepare_time(Time.now - start_time)
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
  PodUpdateConfig.set_prepare_time(Time.now - start_time)
end

# 注册 pod install 钩子
Pod::HooksManager.register('cocoapods-meitu-bin', :post_install) do |context|
  #基于podfile的checksum上报云端podfile.lock文件
  if PodUpdateConfig.is_mtxx
    if PodUpdateConfig.checksum
      upload_podfile_lock(PodUpdateConfig.checksum)
    end
    upload_branch_podfile_lock
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
