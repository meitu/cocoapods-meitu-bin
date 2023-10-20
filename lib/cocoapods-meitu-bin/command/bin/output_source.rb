require 'cocoapods-meitu-bin/helpers/buildAll/builder'
require 'cocoapods-meitu-bin/helpers/buildAll/podspec_util'
require 'cocoapods-meitu-bin/helpers/buildAll/zip_file_helper'
require 'cocoapods-meitu-bin/helpers/buildAll/bin_helper'
require 'cocoapods-meitu-bin/config/config'
require 'yaml'
require 'digest'

module Pod
  class Command
    class Bin < Command
      class OutputSource < Bin
        self.summary = '输出各个组件的source源，默认输出全部组件的source'
        self.description = <<-DESC
          #{summary}
        DESC

        def self.options
          [
            %w[--error-source 过滤异常的source，比如http的，CI打包只支持SSH认证],
            %w[--export-file 导出当前所有tag版本的podspec]
          ].concat(super).uniq
        end

        def initialize(argv)
          @error_source = argv.flag?('error-source', false)
          @export_file = argv.flag?('export-file', false)
          super
        end

        def run
          # 开始时间
          @start_time = Time.now.to_i
          # 更新repo仓库
          repo_update
          # 分析依赖
          @analyze_result = analyse

          if  @error_source
            # 打印source
            show_cost_source
          end

          if  @export_file
            pod_targets = @analyze_result.pod_targets.uniq
            pod_targets.map { |pod_target|
              current_path = Dir.pwd
              spec_path = "#{current_path}/podfile_shell/#{pod_target.root_spec.name}/#{pod_target.root_spec.version.version}/"
              `mkdir -p  #{spec_path}`
              if system("cp #{pod_target.root_spec.defined_in_file.to_s}  #{spec_path} > /dev/null 2>&1")
                puts "#{pod_target.root_spec.name} 的 #{pod_target.root_spec.version.version} 已经导出"
              else
                `rm -rf #{current_path}/podfile_shell/#{pod_target.root_spec.name} > /dev/null 2>&1`
              end
              # puts pod_target.root_spec.name pod_target.root_spec.version.version pod_target.root_spec.defined_in_file
            }
          end
          # 计算耗时
          show_cost_time
        end

        private

        # 打印source
        def show_cost_source
          all_source_list = []
          error_source_list = []
          @analyze_result.specifications.each do |specification|
            all_source_list << { specification.root.name => specification.root.source }
            if @error_source && invalid_git_address?(specification)
              error_source_list << { specification.root.name => specification.root.source }
            end
          end
          if @error_source
            if error_source_list.uniq.empty?
              UI.info "没有有问题的组件".green
            else
              UI.info '问题组件，source 为http CI打包不支持http认证，应修改为ssh'.red
              error_source_list.uniq.map do |source|
                UI.info "- #{source}".red
              end
            end
          else
            UI.info '输出所有pod组件source'.yellow
            all_source_list.uniq.map do |source|
              UI.info "- #{source}"
            end
          end
        end

        # git clone 地址 是否非法
        def invalid_git_address?(specification)
          return false if specification.root.source[:git].nil?
          git = specification.root.source[:git]
          git.include?('http://') || git.include?('https://')
        end

        # 打印耗时
        def show_cost_time
          return if @start_time.nil?
          UI.info "总耗时：#{Time.now.to_i - @start_time}s".green
        end

        # 更新repo仓库
        def repo_update
          if @repo_update
            UI.title 'Repo update'.green do
              return if podfile.nil?
              sources_manager = Pod::Config.instance.sources_manager
              podfile.sources.uniq.map do |src|
                UI.message "Update repo: #{src}"
                source = sources_manager.source_with_name_or_url(src)
                source.update(false)
              end
            end
          end
        end

        # 获取 podfile
        def podfile
          @podfile ||= begin
                         podfile_path = File.join(Pathname.pwd, 'Podfile')
                         raise 'Podfile不存在' unless File.exist?(podfile_path)
                         sources_manager = Pod::Config.instance.sources_manager
                         podfile = Podfile.from_file(Pathname.new(podfile_path))
                         podfile_hash = podfile.to_hash
                         podfile_hash['sources'] = (podfile_hash['sources'] || []).concat(sources_manager.code_source_list.map(&:url))
                         podfile_hash['sources'] << sources_manager.binary_source.url
                         podfile_hash['sources'].uniq!
                         Podfile.from_hash(podfile_hash)
                       end
        end

        # 获取 podfile.lock
        def lockfile
          @lockfile ||= begin
                          lock_path = File.join(Pathname.pwd, 'Podfile.lock')
                          raise 'Podfile.lock不存在，请执行pod install' unless File.exist?(lock_path)
                          Lockfile.from_file(Pathname.new(lock_path))
                        end
        end

        # 获取 sandbox
        def sandbox
          @sandbox ||= begin
                         sandbox_path = File.join(Pathname.pwd, 'Pods')
                         raise 'Pods文件夹不存在，请执行pod install' unless File.exist?(sandbox_path)
                         Pod::Sandbox.new(sandbox_path)
                       end
        end

        # 根据podfile和podfile.lock分析依赖
        def analyse
          UI.title 'Analyze dependencies'.green do
            analyzer = Pod::Installer::Analyzer.new(
              sandbox,
              podfile,
              lockfile
            )
            analyzer.analyze(true)
          end
        end
      end
    end
  end
end
