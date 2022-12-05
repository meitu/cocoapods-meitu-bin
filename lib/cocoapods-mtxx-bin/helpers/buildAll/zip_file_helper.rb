require 'json'
require 'cocoapods-mtxx-bin/helpers/buildAll/bin_helper'

module CBin
  module BuildAll
    class ZipFileHelper
      include Pod

      def initialize(pod_target, version, product_dir, build_as_framework = false, configuration = 'Debug')
        @pod_target = pod_target
        @version = version
        @product_dir = product_dir
        @build_as_framework = build_as_framework
        @configuration = configuration
      end

      # 上传静态库
      def upload_zip_lib
        Dir.chdir(@product_dir) do
          zip_file = File.join(Dir.pwd, "#{zip_file_name}")
          unless File.exist?(zip_file)
            UI.info "`#{Dir.pwd}`目录下无`#{zip_file_name}`文件".red
            return false
          end
          UI.info "Uploading binary zip file `#{@pod_target.root_spec.name} (#{version})`".yellow do
            upload_url = CBin.config.binary_upload_url_str
            xcode_version = BinHelper.xcode_version
            command = "curl -F \"name=#{@pod_target.product_module_name}\" -F \"version=#{version}\" -F \"xcode_version=#{xcode_version}\" -F \"configuration=#{@configuration}\" -F \"file=@#{zip_file}\" #{upload_url}"
            UI.info "#{command}"
            json = `#{command}`
            UI.info json
            begin
              success = JSON.parse(json)["success"]
              if success
                Pod::UI.info "#{@pod_target.root_spec.name} (#{version}) 上传成功".green
                return true
              else
                Pod::UI.info "#{@pod_target.root_spec.name} (#{version}) 上传失败".red
                return false
              end
            rescue JSON::ParserError => e
              Pod::UI.info "#{@pod_target.root_spec.name} (#{version}) 上传失败".red
              Pod::UI.info "#{e.to_s}".red
              return false
            end
          end
        end
      end

      # 压缩静态库
      def zip_lib
        Dir.chdir(@product_dir) do
          input_library = "#{@pod_target.framework_name}"
          output_library = File.join(Dir.pwd, zip_file_name)
          FileUtils.rm_f(output_library) if File.exist?(output_library)
          unless File.exist?(input_library)
            UI.info "没有需要压缩的二进制文件：`#{input_library}`".red
            return false
          end

          UI.info "Compressing `#{input_library}` into `#{zip_file_name}`".yellow do
            command = "zip --symlinks -r #{output_library} #{input_library}"
            UI.info "#{command}"
            `#{command}`
            unless File.exist?(output_library)
              UI.info "压缩`#{output_library}`失败".red
              return false
            end
            return true
          end
        end
      end

      # zip文件名字
      def zip_file_name
        @zip_file_name ||= begin
                             "#{@pod_target.framework_name}_#{@version || @pod_target.root_spec.version}.zip"
                           end
      end

      def version
        @version || @pod_target.root_spec.version
      end

    end
  end
end
