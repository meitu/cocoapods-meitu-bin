
module Pod
  class Command
    class Bin < Command
      class Source < Bin
        class Add < Source

          self.summary = '添加二进制对应源码'
          self.description = <<-DESC
            #{self.summary}
          DESC

          self.arguments = [
            CLAide::Argument.new('NAMES', true )
          ]

          def initialize(argv)
            @names = argv.shift_argument
            super
          end

          def run
            raise Informative, "请输入要添加的Pod库名，多个库中间用逗号隔开" if @names.nil?
            # 依赖分析
            @results = analyse
            # 遍历下载
            @names.split(',').each do |name|
              # 查找二进制spec
              bin_spec = find_specification(name)
              if bin_spec.nil?
                UI.puts "未查找到`#{name}`的二进制spec".red
                next
              end
              # 只有版本号最后一位带`bin`的才有源码
              bin_version = bin_spec.version.to_s
              unless has_source?(bin_version)
                UI.puts "`#{name} (#{bin_version})`已经是源码或无法查看源码".red
                next
              end
              # 查找源码spec
              source_spec = find_source_specification(name, bin_version)
              if source_spec.nil?
                UI.puts "未查找到`#{name}`的源码spec".red
                next
              end
              # 下载源码
              download_source(source_spec)
            end
          end

          private

          # 检查版本号最后一位是否是以`bin`开头的
          def has_source?(version)
            version.split('.').last.include?('bin')
          end

          # 查找二进制spec
          def find_specification(name)
            find_spec = nil
            @results.specifications.each do |spec|
              if spec.root.name.downcase == name.downcase
                find_spec = spec
                break
              end
            end
            find_spec.nil? ? nil : find_spec.root
          end

          # 查找源码spec
          def find_source_specification(name, version)
            source_version = get_source_version(version)
            # 根据 pod_name + version 查找spec
            podfile_sources = config.podfile.sources.uniq.map { |source| config.sources_manager.source_with_name_or_url(source) }
            sources = podfile_sources.select { |s| s.search(name) }
            source_spec = nil
            sources.each do |source|
              begin
                source_spec = source.specification(name, source_version)
                break
              rescue Pod::StandardError => e
                next
              end
            end
            source_spec.nil? ? nil : source_spec.root
          end

          # 下载源码
          def download_source(source_spec)
            UI.title "下载源码:#{source_spec.name} (#{source_spec.version})".green do
              target = target_path(source_spec)
              if exist?(source_spec)
                UI.puts "#{source_spec.name} (#{source_spec.version})源码已经存在".yellow
                return
              end
              download_request = Downloader::Request.new(
                :spec => source_spec,
                :released => true
              )
              FileUtils.mkdir_p(target) unless File.exist?(target)
              Downloader.download(download_request, target, :can_cache => true)
              UI.puts "#{source_spec.name} (#{source_spec.version})源码下载完成!".green
            end
          end

          # 二进制文件路径
          def binary_file(name)
            "#{config.sandbox_root}/#{name}/#{name}.framework/#{name}"
          end

          # 依赖分析
          def analyse
            UI.title 'Analyze dependencies'.green do
              analyzer = Pod::Installer::Analyzer.new(
                config.sandbox,
                config.podfile,
                config.lockfile
              )
              analyzer.analyze(true)
            end
          end

          # 获取源码版本号
          def get_source_version(version)
            source_version = version
            version_arr = version.split('.')
            if version_arr.last.include?('bin')
              version_arr.delete_at(version_arr.size - 1)
              source_version = version_arr.join('.')
            end
            source_version
          end

          # 是否存在对应源码
          def exist?(source_spec)
            target = target_path(source_spec)
            return false unless File.exist?(target)
            entries = Dir.entries(target).reject { |dir| dir == '.' || dir == '..' }
            return false if entries.empty?
            true
          end

        end
      end
    end
  end
end

