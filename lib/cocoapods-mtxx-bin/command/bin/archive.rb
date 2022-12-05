require 'cocoapods-mtxx-bin/native/podfile'
require 'cocoapods/command/gen'
require 'cocoapods/generate'
require 'cocoapods-mtxx-bin/helpers/framework_builder'
require 'cocoapods-mtxx-bin/helpers/library_builder'
require 'cocoapods-mtxx-bin/helpers/build_helper'
require 'cocoapods-mtxx-bin/helpers/spec_source_creator'
require 'cocoapods-mtxx-bin/config/config_builder'
require 'cocoapods-mtxx-bin/command/bin/lib/lint'

module Pod
  class Command
    class Bin < Command
      class Archive < Bin

        @@missing_binary_specs = []

        self.summary = '将组件归档为 .a 或 .framework（目前仅支持静态 framework ）'
        self.description = <<-DESC
          将组件归档为 .a 或 .framework ，仅支持iOS平台

          此静态 framework 不包含依赖组件的 symbol

          目前仅支持 .framework，.a 尚未验证是否可以
        DESC

        def self.options
          [
              ['--all-make', '对该组件的依赖库，全部制作为二进制组件'],
              ['--code-dependencies', '使用源码依赖'],
              ['--no-clean', '保留构建中间产物'],
              ['--sources', '私有源地址，多个用分号区分'],
              ['--framework-output', '输出framework文件'],
              ['--no-zip', '不压缩静态库 为 zip'],
              ['--configuration', 'Build the specified configuration (e.g. Debug). Defaults to Release'],
              ['--env', "该组件上传的环境 %w[dev debug_iphoneos release_iphoneos]"]
          ].concat(Pod::Command::Gen.options).concat(super).uniq
        end

        self.arguments = [
          CLAide::Argument.new('NAME.podspec', false)
        ]

        def initialize(argv)
          @podspec = argv.shift_argument

          @code_dependencies = argv.flag?('code-dependencies')
          @framework_output = argv.flag?('framework-output', false )
          @clean = argv.flag?('no-clean', false)
          @zip = argv.flag?('zip', true)
          @all_make = argv.flag?('all-make', false )
          @sources = argv.option('sources') || []
          @platform = Platform.new(:ios)

          @config = argv.option('configuration', 'Release')

          @framework_path
          super

          @additional_args = argv.remainder!
          @build_finshed = false
        end

        def run
          # 清除之前的缓存
          zip_dir = CBin::Config::Builder.instance.zip_dir
          FileUtils.rm_rf(zip_dir) if File.exist?(zip_dir)
          # 加载podspec
          @spec = Specification.from_file(spec_file)
          # 如果有 default_subspecs 报错提示
          raise Informative, "#{@spec.root.name} (#{@spec.root.version}) 有default_subspecs：#{@spec.default_subspecs}，请注释掉重新执行命令！" unless @spec.default_subspecs.empty?
          # 生成xcode工程
          generate_project
          # 构建当前库
          build_root_spec

          sources_sepc = Array.new
          sources_sepc << @spec
          # 如果有 --all-make 选项，则打包依赖组件

          sources_sepc.concat(build_dependencies) if @all_make

          # 返回所有打包二进制组件的podspec
          sources_sepc
        end

        # 构建当前库
        def build_root_spec
          builder = CBin::Build::Helper.new(@spec,
                                            @platform,
                                            @framework_output,
                                            @zip,
                                            @spec,
                                            CBin::Config::Builder.instance.white_pod_list.include?(@spec.name),
                                            @config,
                                            @installers.size > 0 ? @installers[0] : nil)
          builder.build
          builder.clean_workspace if @clean && !@all_make
        end

        # 构建依赖库
        def build_dependencies
          @build_finshed = true
          #如果没要求，就清空依赖库数据
          sources_sepc = []
          @@missing_binary_specs.uniq.each do |spec|
            next if spec.name.include?('/') # 过滤subspec
            next if spec.name == @spec.name  # 过滤当前库
            #过滤白名单
            next if CBin::Config::Builder.instance.white_pod_list.include?(spec.name)
            #过滤 git
            if spec.source[:git] && spec.source[:git]
              spec_git = spec.source[:git]
              spec_git_res = false
              CBin::Config::Builder.instance.ignore_git_list.each do |ignore_git|
                spec_git_res = spec_git.include?(ignore_git)
                break if spec_git_res
              end
              next if spec_git_res
            end
            UI.warn "#{spec.name}.podspec 带有 vendored_frameworks 字段，请检查是否有效！！！" if spec.attributes_hash['vendored_frameworks']
            UI.warn "#{spec.name}.podspec 带有 vendored_libraries 字段，请检查是否有效！！！" if spec.attributes_hash['vendored_libraries']
            next if (spec.attributes_hash['vendored_frameworks'] || spec.attributes_hash['vendored_libraries']) && @spec.name != spec.name
            next if (spec.attributes_hash['ios.vendored_frameworks'] || spec.attributes_hash['ios.vendored_libraries']) && @spec.name != spec.name
            #获取没有制作二进制版本的spec集合
            sources_sepc << spec
          end

          fail_build_specs = []
          sources_sepc.uniq.each do |spec|
            begin
              builder = CBin::Build::Helper.new(spec,
                                                @platform,
                                                @framework_output,
                                                @zip,
                                                @spec,
                                                false ,
                                                @config,
                                                nil )
              builder.build
            rescue Object => exception
              UI.puts exception
              fail_build_specs << spec
            end
          end

          if fail_build_specs.any?
            fail_build_specs.uniq.each do |spec|
              UI.warn "【#{spec.name} | #{spec.version}】组件二进制版本编译失败 ."
            end
          end
          sources_sepc - fail_build_specs
        end

        # 解析器传过来的
        def Archive.missing_binary_specs(missing_binary_specs)
          @@missing_binary_specs = missing_binary_specs unless @build_finshed
        end

        private

        # 生成xcode工程
        def generate_project
          Podfile.execute_with_bin_plugin do
            Podfile.execute_with_use_binaries(!@code_dependencies) do
                argvs = [
                  "--sources=#{sources_option(@code_dependencies, @sources)},https:\/\/cdn.cocoapods.org",
                  "--gen-directory=#{CBin::Config::Builder.instance.gen_dir}",
                  '--clean',
                  *@additional_args
                ]

                podfile= File.join(Pathname.pwd, "Podfile")
                if File.exist?(podfile)
                  argvs += ['--use-podfile']
                  argvs += ["--podfile-path=#{podfile}"]
                end
                
                argvs << spec_file if spec_file

                gen = Pod::Command::Gen.new(CLAide::ARGV.new(argvs))
                gen.validate!
                @installers = gen.run
            end
          end
        end

        # 查找podspec
        def spec_file
          @spec_file ||= begin
                           if @podspec
                             find_spec_file(@podspec)
                           else
                             if code_spec_files.empty?
                               raise Informative, '当前目录下没有找到可用源码 podspec.'
                             end

                             spec_file = code_spec_files.first
                             spec_file
                           end
                         end
        end
      end
    end
  end
end
