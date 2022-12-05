require 'yaml'
require 'cocoapods-mtxx-bin/native/podfile'
require 'cocoapods-mtxx-bin/native/podfile_env'
require 'cocoapods/generate'

module CBin
  class Config
    def config_file
      config_file_with_configuration_env(configuration_env)
    end

    def template_hash
      {
          'configuration_env' => { description: '编译环境', default: 'dev', selection: %w[dev debug_iphoneos release_iphoneos] },
          'binary_repo_url' => { description: '二进制podspec私有源地址', default: 'git@github.com:Zhangyanshen/example-private-spec-bin.git' },
          'binary_upload_url' => { description: '二进制文件上传地址', default: 'http://localhost:8080/frameworks' },
          'binary_download_url' => { description: '二进制文件下载地址，后面会依次传入Xcode版本、configuration、组件名称与组件版本', default: 'http://localhost:8080/frameworks' },
          'download_file_type' => { description: '二进制文件类型', default: 'zip', selection: %w[zip tgz tar tbz txz dmg] }
      }
    end

    def config_file_with_configuration_env(configuration_env)
      file = config_dev_file
      if configuration_env == "release_iphoneos"
        file = config_release_iphoneos_file
      elsif configuration_env == "debug_iphoneos"
        file = config_debug_iphoneos_file
      elsif configuration_env == "dev"
        file = config_dev_file
      else
        raise "===== #{configuration_env} %w[dev debug_iphoneos release_iphoneos]===="
      end

      File.expand_path("#{Pod::Config.instance.project_root}/#{file}")
    end

    def configuration_env
      #如果是dev 再去 podfile的配置文件中获取，确保是正确的， pod update时会用到
      if @configuration_env == "dev" || @configuration_env == nil
        if Pod::Config.instance.podfile
          configuration_env ||= Pod::Config.instance.podfile.configuration_env
        end
        configuration_env ||= "dev"
        @configuration_env = configuration_env
      end
      @configuration_env
    end

    # 上传二进制的url
    def binary_upload_url_str
      CBin.config.binary_upload_url
    end

    # 下载二进制的url
    def binary_download_url_str
      CBin.config.binary_download_url
    end

    def set_configuration_env(env)
      @configuration_env = env
    end

    #包含arm64  armv7架构，xcodebuild 是Debug模式
    def config_debug_iphoneos_file
      ".bin_debug_iphoneos.yml"
    end
    #包含arm64  armv7架构，xcodebuild 是Release模式
    def config_release_iphoneos_file
      ".bin_release_iphoneos.yml"
    end
    #包含x86 arm64  armv7架构，xcodebuild 是Release模式
    def config_dev_file
      ".bin_dev.yml"
    end

    # 配置信息写入文件
    def sync_config(config)
      File.open(config_file_with_configuration_env(config['configuration_env']), 'w+') do |f|
        f.write(config.to_yaml)
      end
    end

    # def sync_config_code_repo_url_list(config)
    #   File.open(config_file_with_configuration_env_list(config['code_repo_url_list']), 'w+') do |f|
    #     f.write(config.to_yaml)
    #   end
    # end

    def default_config
      @default_config ||= Hash[template_hash.map { |k, v| [k, v[:default]] }]
    end

    private

    def load_config
      if File.exist?(config_file)
        YAML.load_file(config_file)
      else
        default_config
      end
    end

    def config
      @config ||= begin
                    @config = OpenStruct.new load_config
        validate!
        @config
      end
    end

    def validate!
      template_hash.each do |k, v|
        selection = v[:selection]
        next if !selection || selection.empty?

        config_value = @config.send(k)
        next unless config_value
        unless selection.include?(config_value)
          raise Pod::Informative, "#{k} 字段的值必须限定在可选值 [ #{selection.join(' / ')} ] 内".red
        end
      end
    end

    def respond_to_missing?(method, include_private = false)
      config.respond_to?(method) || super
    end

    def method_missing(method, *args, &block)
      if config.respond_to?(method)
        config.send(method, *args)
      elsif template_hash.keys.include?(method.to_s)
        raise Pod::Informative, "#{method} 字段必须在配置文件 #{config_file} 中设置, 请执行 init 命令配置或手动修改配置文件".red
      else
        super
      end
    end

    public

    # 判断配置文件是否存在
    def config_file_exist?
      raise Pod::Informative, "当前目录下没有配置文件，请先执行`pod bin init`" unless File.exist?(config_file)
    end
  end

  def self.config
    @config ||= Config.new
  end
end
