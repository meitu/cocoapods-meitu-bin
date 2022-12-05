require 'cocoapods'
require 'cocoapods-mtxx-bin/config/config'

module CBin
  class SpecificationSource
    class Creator
      attr_reader :code_spec
      attr_reader :spec

      def initialize(code_spec, platforms = 'ios')
        @code_spec = code_spec
        @platforms = Array(platforms)
        validate!
      end

      def validate!
        raise Pod::Informative, '源码 podspec 不能为空 .' unless code_spec
      end

      # 创建二进制podspec
      def create
        # spec = nil
        if CBin::Build::Utils.is_framework(@code_spec)
          # .framework
          spec = create_framework_from_code_spec
        else
          # .a
          spec = create_from_code_spec
        end

        spec
      end

      # 将二进制podspec写入文件
      def write_spec_file(file = filename)
        create unless spec

        FileUtils.mkdir_p(CBin::Config::Builder.instance.binary_json_dir) unless File.exist?(CBin::Config::Builder.instance.binary_json_dir)
        FileUtils.rm_rf(file) if File.exist?(file)

        File.open(file, 'w+') do |f|
          # f.write("# MARK: converted automatically by plugin cocoapods-mtxx-bin @slj \r\n")
          f.write(spec.to_pretty_json)
        end

        @filename = file
      end

      def clear_spec_file
        File.delete(filename) if File.exist?(filename)
      end

      def filename
        @filename ||= "#{CBin::Config::Builder.instance.binary_json_dir_name}/#{spec.name}.binary.podspec.json"
      end

      private

      # 创建.a的二进制podspec
      def create_from_code_spec
        @spec = code_spec.dup
        # vendored_frameworks | resources | source | source_files | public_header_files
        # license | resource_bundles | vendored_libraries

        # Project Linkin
        # @spec.vendored_frameworks = "#{code_spec.root.name}.framework"

        # Resources
        extnames = []
        extnames << '*.bundle' if code_spec_consumer.resource_bundles.any?
        if code_spec_consumer.resources.any?
          extnames += code_spec_consumer.resources.map { |r| File.basename(r) }
        end
        if extnames.any?
          @spec.resources = framework_contents('').flat_map { |r| extnames.map { |e| "#{r}/#{e}" } }
        end

        # Source Location
        @spec.source = binary_source

        # Source Code
        @spec.source_files = framework_contents('Headers/*')
        @spec.public_header_files = framework_contents('Headers/*')

        # Unused for binary
        spec_hash = @spec.to_hash
        # spec_hash.delete('license')
        spec_hash.delete('source_files')
        spec_hash.delete('resource_bundles')
        spec_hash.delete('exclude_files')
        spec_hash.delete('preserve_paths')

        spec_hash.delete('subspecs')
        spec_hash.delete('default_subspecs')
        spec_hash.delete('default_subspec')
        spec_hash.delete('vendored_frameworks')
        spec_hash.delete('vendored_framework')

        # 这里不确定 vendored_libraries 指定的时动态/静态库
        # 如果是静态库的话，需要移除，否则就不移除
        # 最好是静态库都独立成 Pod ，cocoapods-package 打静态库去 collect 目标文件时好做过滤
        # 这里统一只对命名后缀 .a 文件做处理
        # spec_hash.delete('vendored_libraries')
        # libraries 只能假设为动态库不做处理了，如果有例外，需要开发者自行处理
        spec_hash.delete('vendored_libraries')

        # vendored_libraries = Array(vendored_libraries).reject { |l| l.end_with?('.a') }
        # if vendored_libraries.any?
        #   spec_hash['vendored_libraries'] = vendored_libraries
        # end

        # Filter platforms
        platforms = spec_hash['platforms']
        selected_platforms = platforms.select { |k, _v| @platforms.include?(k) }
        spec_hash['platforms'] = selected_platforms.empty? ? platforms : selected_platforms

        @spec = Pod::Specification.from_hash(spec_hash)

        #把命令 prepare_command 移除掉，如ReactiveCocoa会执行修改重命令的脚步
        @spec.prepare_command = "" if @spec.prepare_command
        @spec.version = code_spec.version
        @spec.source = binary_source
        @spec.source_files = binary_source_files
        @spec.public_header_files = binary_public_header_files
        @spec.vendored_libraries = binary_vendored_libraries
        @spec.resources = binary_resources if @spec.attributes_hash.keys.include?("resources")
        @spec.description = <<-EOF
         「converted automatically by plugin cocoapods-mtxx-bin @美图 - zys」
          #{@spec.description}
        EOF
        @spec
      end

      # 创建.framework的二进制podspec
      def create_framework_from_code_spec
        @spec = code_spec.dup
        # vendored_frameworks | resources | source | source_files | public_header_files
        # license | resource_bundles | vendored_libraries

        # framework绝对路径
        fwk_abs_path = "#{CBin::Config::Builder.instance.gen_dir}/#{code_spec.root.name}/ios/#{code_spec.module_name}.framework"

        # Project Linkin
        fwks_path = "#{fwk_abs_path}/fwks"
        fwks = ["#{code_spec.module_name}.framework"]
        if File.exist?(fwks_path)
          fwks << "#{code_spec.module_name}.framework/fwks/*"
        end
        @spec.vendored_frameworks = fwks

        libs_path = "#{fwk_abs_path}/libs"
        @spec.vendored_libraries = "#{code_spec.module_name}.framework/libs/*" if File.exist?(libs_path)

        # Resources
        special_resource_ext_str = special_resource_exts.join(',')
        special_res = Dir.glob("#{fwk_abs_path}/*.{#{special_resource_ext_str}}")
        resources = []
        unless special_res.empty?
          resources << "#{code_spec.module_name}.framework/*.{#{special_resource_ext_str}}"
        end
        resources_path = "#{fwk_abs_path}/resources"
        if File.exist?(resources_path)
          resources << "#{code_spec.module_name}.framework/resources/*"
        end
        @spec.resources = resources unless resources.empty?

        # Source Location
        @spec.source = binary_source
        # Source Code
        @spec.source_files = "#{code_spec.module_name}.framework/Headers/*"
        @spec.public_header_files = "#{code_spec.module_name}.framework/Headers/*"
        @spec.private_header_files = "#{code_spec.module_name}.framework/PrivateHeaders/*"

        # Unused for binary
        spec_hash = @spec.to_hash
        # spec_hash.delete('license')
        # spec_hash.delete('source_files')
        spec_hash.delete('project_header_files')
        spec_hash.delete('resource_bundles')
        spec_hash.delete('exclude_files')
        spec_hash.delete('preserve_paths')
        spec_hash.delete('prepare_command')
        # 这里不确定 vendored_libraries 指定的时动态/静态库
        # 如果是静态库的话，需要移除，否则就不移除
        # 最好是静态库都独立成 Pod ，cocoapods-package 打静态库去 collect 目标文件时好做过滤
        # 这里统一只对命名后缀 .a 文件做处理
        # spec_hash.delete('vendored_libraries')
        # libraries 只能假设为动态库不做处理了，如果有例外，需要开发者自行处理
        # vendored_libraries = spec_hash.delete('vendored_libraries')
        # vendored_libraries = Array(vendored_libraries).reject { |l| l.end_with?('.a') }
        # if vendored_libraries.any?
        #   spec_hash['vendored_libraries'] = vendored_libraries
        # end

        # Filter platforms
        platforms = spec_hash['platforms']
        selected_platforms = platforms.select { |k, _v| @platforms.include?(k) }
        spec_hash['platforms'] = selected_platforms.empty? ? platforms : selected_platforms

        # subspecs
        if spec_hash['subspecs'] && spec_hash['subspecs'].size > 0
          bin_subspec = {
            'name' => 'Binary',
            'source_files' => spec_hash['source_files'],
            'public_header_files' => spec_hash['public_header_files'],
            'private_header_files' => spec_hash['private_header_files'],
            'vendored_frameworks' => spec_hash['vendored_frameworks'],
            'vendored_libraries' => spec_hash['vendored_libraries'],
            'resources' => spec_hash['resources']
          }
          spec_hash['subspecs'] << bin_subspec
          spec_hash['subspecs'].map do |subspec|
            next if subspec['name'] == 'Binary'
            # 处理单个subspec
            handle_single_subspec(subspec)
            # 递归处理subspec
            handle_subspecs(subspec['subspecs'])
          end
        end

        @spec = Pod::Specification.from_hash(spec_hash)
        @spec.description = <<-EOF
         「converted automatically by plugin cocoapods-mtxx-bin @美图 - zys」
          #{@spec.description}
        EOF
        @spec
      end

      # 特殊的资源后缀
      def special_resource_exts
        %w[momd mom cdm nib storyboardc]
      end

      # 递归处理subspecs
      def handle_subspecs(subspecs)
        return unless subspecs && subspecs.size > 0
        subspecs.map do |s|
          # 处理单个subspec
          handle_single_subspec(s)
          # 递归处理
          handle_subspecs(s['subspecs'])
        end
      end

      # 处理单个subspec
      def handle_single_subspec(subspec)
        subspec.delete('source_files')
        subspec.delete('public_header_files')
        subspec.delete('project_header_files')
        subspec.delete('private_header_files')
        subspec.delete('vendored_frameworks')
        subspec.delete('vendored_libraries')
        subspec.delete('resource_bundles')
        subspec.delete('resources')
        subspec.delete('exclude_files')
        subspec.delete('preserve_paths')
        if subspec['dependencies']
          subspec['dependencies']["#{code_spec.root.name}/Binary"] = []
        else
          subspec['dependencies'] = {"#{code_spec.root.name}/Binary": []}
        end
      end

      # "source"字段
      def binary_source
        url = "#{CBin.config.binary_download_url_str}/#{code_spec.root.module_name}/#{code_spec.version}/#{code_spec.root.module_name}.framework_#{code_spec.version}.zip"
        { http: url, type: CBin.config.download_file_type }
      end

      def code_spec_consumer(_platform = :ios)
        code_spec.consumer(:ios)
      end

      def framework_contents(name)
        # ["#{code_spec.root.name}.framework", "#{code_spec.root.name}.framework/Versions/A"].map { |path| "#{path}/#{name}" }
        ["#{code_spec.module_name}.framework"]
      end

      def binary_source_files
        "bin_#{code_spec.name}_#{code_spec.version}/Headers/*"
      end

      def binary_public_header_files
        "bin_#{code_spec.name}_#{code_spec.version}/Headers/*.h"
      end

      def binary_vendored_libraries
        "bin_#{code_spec.name}_#{code_spec.version}/*.a"
      end

      def binary_resources
        "bin_#{code_spec.name}_#{code_spec.version}/Resources/*"
      end

    end
  end
end
#模板框架begin
#     s.source_files = "bin_#{s.name}_#{s.version}/Headers/*"
#     s.public_header_files = "bin_#{s.name}_#{s.version}/Headers/*.h"
#     s.vendored_libraries = "bin_#{s.name}_#{s.version}/*.a"
#有图片资源的，要带上
#s.resources = 'bin_#{s.name}_#{s.version}/Resources/*.{json,png,jpg,gif,js,xib,eot,svg,ttf,woff,db,sqlite,mp3,bundle}'
#模板框架end