require 'cocoapods-mtxx-bin/command/bin/auto'
require 'cocoapods-mtxx-bin/helpers/upload_helper'

module Pod
  class Command
    class Bin < Command
      class Auto < Bin
        self.summary = '一键打包二进制并上传'
        self.description = <<-DESC
          生成二进制文件并上传至文件服务器，生成二进制 podspec 并上传至二进制私有源
        DESC

        self.arguments = [
            CLAide::Argument.new('NAME.podspec', false)
        ]
        def self.options
          [
              ['--push-source-podspec', '上传源码 podspec '],
              ['--code-dependencies', '使用源码依赖'],
              ['--allow-prerelease', '允许使用 prerelease 的版本'],
              ['--no-clean', '保留构建中间产物'],
              ['--framework-output', '输出framework文件'],
              ['--no-zip', '不压缩静态 framework 为 zip'],
              ['--all-make', '对该组件的依赖库，全部制作为二进制组件'],
              ['--configuration', 'Build the specified configuration (e.g. Release ). Defaults to Debug'],
              ['--env', "该组件上传的环境 %w[dev debug_iphoneos release_iphoneos]"]
          ].concat(Pod::Command::Gen.options).concat(super).uniq
        end

        def initialize(argv)

          @env = argv.option('env') || 'dev'
          CBin.config.set_configuration_env(@env)

          # @podspec = argv.shift_argument || find_podspec
          @podspec = argv.shift_argument

          @push_source_podspec = argv.flag?('push-source-podspec')
          @code_dependencies = argv.flag?('code-dependencies')
          @allow_prerelease = argv.flag?('allow-prerelease')
          @framework_output = argv.flag?('framework-output', false)
          @clean = argv.flag?('clean', true)
          @zip = argv.flag?('zip', true)
          @all_make = argv.flag?('all-make', false)
          @verbose = argv.flag?('verbose', false)
          @sources = argv.option('sources', 'https://cdn.cocoapods.org')
          @config = argv.option('configuration', 'Release')

          super

          # ！！！ 这一行加载在 super 的后面，否则会出现问题，切记 ！！！
          @additional_args = argv.remainder!
        end

        def validate!
          super
          raise Informative, '当前目录下没有 podspec 文件' if @podspec.nil? && code_spec_files.size == 0
          raise Informative, '当前目录有多个 podspec 文件，请指定具体的 podspec 文件' if @podspec.nil? && code_spec_files.size > 1
        end

        def run
          @podspec = find_podspec unless @podspec
          @specification = Specification.from_file(@podspec)

          # 归档.a或.framework
          sources_sepc = run_archive

          fail_push_specs = []
          sources_sepc.uniq.each do |spec|
            begin
              # 上传所有打包好的二进制文件及podspec
              fail_push_specs << spec unless CBin::Upload::Helper.new(spec,@code_dependencies,@sources).upload
            rescue  Object => exception
              UI.puts exception
              fail_push_specs << spec
            end
          end

          if fail_push_specs.any?
            fail_push_specs.uniq.each do |spec|
              UI.warn "【#{spec.name} | #{spec.version}】组件spec push失败 ."
            end
          end

          success_specs = sources_sepc - fail_push_specs
          if success_specs.any?
            auto_success = ""
            success_specs.uniq.each do |spec|
              auto_success += "#{spec.name} | #{spec.version}\n"
              UI.message "【 #{spec.name} | #{spec.version} 】二进制组件制作完成".green
            end
            UI.message auto_success
            ENV['auto_success'] = auto_success
          end
          #pod repo update
          UI.title("Updating Spec Repositories\n".yellow) do
            Pod::Command::Bin::Repo::Update.new(CLAide::ARGV.new([])).run
          end

          # 上传源码podspec
          UI.title("Pushing source podspec for #{@specification.name}") do
            Pod::Command::Bin::Repo::Push.new(CLAide::ARGV.new([@podspec, '--loose-options'])).run
          end if @push_source_podspec

        end

        #制作二进制包
        def run_archive
          argvs = [
              "--sources=#{sources_option(@code_dependencies, @sources)},https:\/\/cdn.cocoapods.org"
          ]

          argvs += @additional_args unless @additional_args.nil?

          argvs << @podspec if @podspec
          argvs.delete(Array.new)

          unless @clean
            argvs += ['--no-clean']
          end
          if @code_dependencies
            argvs += ['--code-dependencies']
          end
          if @verbose
            argvs += ['--verbose']
          end
          if @allow_prerelease
            argvs += ['--allow-prerelease']
          end
          if @framework_output
            argvs += ['--framework-output']
          end
          if @all_make
            argvs += ['--all-make']
          end
          # if @env
          #   argvs += ["--env=#{@env}"]
          # end
          argvs += ["--configuration=#{@config}"]
          
          archive = Pod::Command::Bin::Archive.new(CLAide::ARGV.new(argvs))
          archive.validate!
          sources_sepc = archive.run
          sources_sepc
        end

        def code_podsepc_extname
          '.podsepc'
        end

        def binary_podsepc_json
          "#{@specification.name}.binary.podspec.json"
        end

        def binary_template_podsepc
          "#{@specification.name}.binary-template.podspec"
        end

        def template_spec_file
          @template_spec_file ||= begin
                                    if @template_podspec
                                      find_spec_file(@template_podspec)
                                    else
                                      binary_template_spec_file
                                    end
                                  end
        end

        def spec_file
          @spec_file ||= begin
                           if @podspec
                             find_spec_file(@podspec) || @podspec
                           else
                             if code_spec_files.empty?
                               raise Informative, '当前目录下没有找到可用源码 podspec.'
                             end

                             spec_file = if @binary
                                           code_spec = Pod::Specification.from_file(code_spec_files.first)
                                           if template_spec_file
                                             template_spec = Pod::Specification.from_file(template_spec_file)
                                           end
                                           create_binary_spec_file(code_spec, template_spec)
                                         else
                                           code_spec_files.first
                                         end
                             spec_file
                           end
                         end
        end

        #Dir.glob 可替代
        def find_podspec
          name = nil
          Pathname.pwd.children.each do |child|
            # puts child
            if File.file?(child)
              if child.extname == '.podspec'
                  name = File.basename(child)
                  unless name.include?("binary-template")
                    return name
                  end
              end
            end
          end
          return name
        end

      end
    end
  end
end
