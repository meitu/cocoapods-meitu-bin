require 'cocoapods-mtxx-bin/config/config_asker'

module Pod
  class Command
    class Bin < Command
      class Init < Bin
        self.summary = '配置插件'
        self.description = <<-DESC
          创建yml配置文件，保存插件需要的配置信息，如二进制podspec仓库、二进制下载地址等
        DESC

        def self.options
          [
            %w[--bin-url=URL 配置文件地址，直接从此地址下载配置文件]
          ].concat(super)
        end

        def initialize(argv)
          @bin_url = argv.option('bin-url')
          super
        end

        def run
          raise Informative, "当前目录下没有`Podfile`文件" unless File.exist?(File.join(Dir.pwd, "Podfile"))
          raise Informative, "当前目录下已经存在配置文件" if File.exist?(CBin.config.config_file)
          if @bin_url.nil?
            config_with_asker
          else
            config_with_url(@bin_url)
          end
        end

        private

        # 从远端下载配置文件
        def config_with_url(url)
          require 'open-uri'

          UI.puts "开始下载配置文件..."
          file = open(url)
          contents = YAML.safe_load(file.read)

          UI.puts "开始同步配置文件..."
          CBin.config.sync_config(contents.to_hash)
          UI.puts "设置完成.".green
        rescue Errno::ENOENT => e
          raise Informative, "配置文件路径 #{url} 无效，请确认后重试."
        end

        # 询问用户相关的配置
        def config_with_asker
          asker = CBin::Config::Asker.new
          asker.welcome_message

          config = {}
          template_hash = CBin.config.template_hash
          template_hash.each do |k, v|
            default = begin
                        CBin.config.send(k)
                      rescue StandardError
                        nil
                      end
            config[k] = asker.ask_with_answer(v[:description], default, v[:selection])
          end

          CBin.config.sync_config(config)
          asker.done_message
        end
      end
    end
  end
end
