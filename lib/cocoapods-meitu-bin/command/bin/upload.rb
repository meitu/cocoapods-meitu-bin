require 'json'
require 'cocoapods-meitu-bin/helpers/buildAll/bin_helper'

module Pod
  class Command
    class Bin < Command
      class Upload < Bin
        include Pod

        self.summary = "上传二进制文件及podspec"
        self.description = <<-DESC
#{self.summary}

`NAME`: 库名【必填】\n
`VERSION`: 版本号【必填】\n
`FILE`: 需要压缩的二进制文件或目录【必填】\n
`REPO`: 上传podspec的仓库，可以通过`pod repo list`查看【必填】\n

e.g.:\n
pod bin upload Pod1 1.0.0 Pod1.framework mtxxspecs --spec=Pod1.podspec
        DESC

        self.arguments = [
          CLAide::Argument.new('NAME', true ),
          CLAide::Argument.new('VERSION', true),
          CLAide::Argument.new('FILE', true),
          CLAide::Argument.new('REPO', true)
        ]

        def self.options
          [
            %w[--spec=SPEC 指定podspec文件路径，如果不指定，将在当前目录下查找]
          ].concat(super)
        end

        def initialize(argv)
          @name = argv.shift_argument
          @version = argv.shift_argument
          @file = argv.shift_argument
          @repo = argv.shift_argument
          @spec = argv.option('spec', nil)
          @xcode_version = CBin::BuildAll::BinHelper.xcode_version
          super
        end

        def run
          # 参数检查
          argvsCheck
          # 压缩文件
          zip_file
          # 上传文件
          upload_zip_file
          # 修改podspec
          modify_spec
          # 上传podspec
          upload_spec
        end

        private

        # 参数检查
        def argvsCheck
          raise Informative, "name不能为空" if @name.nil?
          raise Informative, "version不能为空" if @version.nil?
          raise Informative, "repo不能为空" if @repo.nil?
          raise Informative, "未找到需要压缩的二进制文件" if @file.nil?
          raise Informative, "未找到podspec文件" unless File.exist?(podspec)
        end

        # 压缩文件
        def zip_file
          UI.title "压缩二进制文件`#{zip_file_name}`".yellow do
            output_zip_file = File.join(Dir.pwd, zip_file_name)
            FileUtils.rm_f(output_zip_file) if File.exist?(output_zip_file)
            command = "zip --symlinks -r #{zip_file_name} #{@file}"
            UI.info "#{command}"
            `#{command}`
            raise Informative, "压缩二进制文件失败" unless File.exist?(output_zip_file)
          end
        end

        # 压缩后的zip包名
        def zip_file_name
          @zip_file_name ||= begin
                               "#{@name}_#{@version}.zip"
                             end
        end

        # 上传文件
        def upload_zip_file
          UI.title "上传二进制文件`#{zip_file_name}`".yellow do
            zip_file = File.join(Dir.pwd, zip_file_name)
            raise Informative, "`#{@zip_file_name}`不存在" unless File.exist?(zip_file)
            upload_url = CBin.config.binary_upload_url_str
            command = "curl -F \"name=#{@name}\" -F \"version=#{@version}\" -F \"file=@#{zip_file}\" #{upload_url}"
            UI.info "#{command}"
            json = `#{command}`
            UI.info json
            begin
              error_code = JSON.parse(json)["error_code"]
              raise Informative, "`#{zip_file_name}`上传失败" unless error_code == 0
              UI.info "`#{zip_file_name}`上传成功".green
            rescue JSON::ParserError => e
              raise Informative, "`#{zip_file_name}`上传失败\n#{e.to_s}"
            end
          end
        end

        # 修改podspec
        def modify_spec
          UI.title "修改podspec：`#{podspec}`".yellow do
            spec = Specification.from_file(podspec)
            spec_hash = spec.to_hash
            spec_hash['version'] = @version
            spec_hash['source'] = source
            spec = Specification.from_hash(spec_hash)
            write_podspec_json(spec)
          end
        end

        # 写入podspec
        def write_podspec_json(spec)
          FileUtils.rm_f(podspec_json_file) if File.exist?(podspec_json_file)
          File.open(podspec_json_file, "w+") do |f|
            f.write(spec.to_pretty_json)
          end
        end

        def source
          url = "#{CBin.config.binary_download_url_str}/#{@xcode_version}/#{@name}/#{@version}/#{zip_file_name}"
          { http: url, type: CBin.config.download_file_type }
        end

        # 上传podspec
        def upload_spec
          UI.title "推送podspec：`#{podspec_json_file_name}`".yellow do
            raise Informative, "`#{podspec_json_file_name}`不存在" unless File.exist?(podspec_json_file)
            argvs = %W[#{@repo} #{podspec_json_file} --skip-import-validation --use-libraries --allow-warnings --verbose]

            begin
              push = Pod::Command::Repo::Push.new(CLAide::ARGV.new(argvs))
              push.validate!
              push.run
            rescue Pod::StandardError => e
              raise Informative, "推送podspec：`#{podspec_json_file_name}失败\n#{e.to_s}"
            end
            # 上传完成后，清理工作目录
            FileUtils.rm_f(podspec_json_file) if File.exist?(podspec_json_file)
            FileUtils.rm_r('binary') if File.exist?('binary')
            FileUtils.rm_f(zip_file_name) if File.exist?(zip_file_name)
          end
        end

        def binary_dir
          File.join(Dir.pwd, 'binary')
        end

        def podspec_json_file_name
          "#{@name}.podspec.json"
        end

        def podspec_json_file
          File.join(Dir.pwd, podspec_json_file_name)
        end

        def podspec
          @spec ||= begin
                      "#{@name}.podspec"
                    end
        end

      end
    end
  end
end
