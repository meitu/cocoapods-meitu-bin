# copy from https://github.com/CocoaPods/cocoapods-packager

require 'cocoapods-mtxx-bin/helpers/framework.rb'
require 'English'
require 'cocoapods-mtxx-bin/config/config_builder'
require 'shellwords'

module CBin
  class Framework
    class Builder
      include Pod
#Debug下还待完成
      def initialize(spec, installer, platform, source_dir, isRootSpec = true, build_model="Release")
        @spec = spec
        @source_dir = source_dir
        @installer = installer
        @platform = platform
        @build_model = build_model
        @isRootSpec = isRootSpec

        @file_accessors = @installer.pod_targets.select { |t| t.pod_name == @spec.name }.flat_map(&:file_accessors) if installer
      end

      # 利用xcodebuild打包
      def build
        defines = compile
        build_sim_libraries(defines)

        defines
      end

      def lipo_create(defines)
        # 合并静态库
        merge_static_libs
        # 拷贝资源文件
        copy_all_resources
        # 拷贝swiftmodule
        copy_swiftmodules
        # # 拷贝vendored_libraries
        # copy_vendored_libraries
        # 拷贝vendored_frameworks
        copy_vendored_frameworks
        # # 拷贝动态库
        # copy_dynamic_libs
        # # 拷贝xcframework
        # copy_xcframeworks
        # 拷贝最终产物
        copy_target_product
        # 返回Framework目录
        framework
      end

      private

      # 拷贝最终产物
      def copy_target_product
        framework
        fwk = "#{build_device_dir}/#{framework_name}.framework"
        `cp -r #{fwk} #{framework.root_path}`
      end

      # 拷贝xcframework
      def copy_xcframeworks
        xcframeworks = vendored_xcframeworks
        unless xcframeworks.empty?
          des_dir = dynamic_libs_des_dir
          FileUtils.mkdir(des_dir) unless File.exist?(des_dir)
          xcframeworks.map { |xcf| `cp -r #{xcf} #{des_dir}` }
        end
      end

      # 拷贝动态库
      def copy_dynamic_libs
        dynamic_libs = vendored_dynamic_libraries
        if dynamic_libs && dynamic_libs.size > 0
          des_dir = dynamic_libs_des_dir
          FileUtils.mkdir(des_dir) unless File.exist?(des_dir)
          dynamic_libs.map { |lib| `cp -r #{lib} #{des_dir}` }
        end
      end

      # 拷贝vendored_frameworks
      def copy_vendored_frameworks
        fwks = vendored_frameworks
        unless fwks.empty?
          des_dir = dynamic_libs_des_dir
          FileUtils.mkdir(des_dir) unless File.exist?(des_dir)
          fwks.map { |fwk| `cp -r #{fwk} #{des_dir}` }
        end
      end

      # 拷贝vendored_libraries
      def copy_vendored_libraries
        libs = vendored_libraries
        unless libs.empty?
          des_dir = vendored_libraries_dir
          FileUtils.mkdir(des_dir) unless File.exist?(des_dir)
          libs.map { |lib| `cp -r #{lib} #{des_dir}` }
        end
      end

      # 拷贝swiftmodule
      def copy_swiftmodules
        swift_module = "#{build_device_dir}/#{framework_name}.framework/Modules/#{framework_name}.swiftmodule"
        if File.exist?(swift_module)
          src_swift = "#{build_sim_dir}/#{framework_name}.framework/Modules/#{framework_name}.swiftmodule"
          `cp -af #{src_swift}/* #{swift_module}`
          `cp -af #{src_swift}/Project/* #{swift_module}/Project`
        end
      end

      # 拷贝资源文件
      def copy_all_resources
        # 拷贝resource_bundles
        copy_resource_bundles
        # 拷贝resources/resource
        copy_other_resources
      end

      # 拷贝resource_bundles
      def copy_resource_bundles
        bundles = resource_bundles
        return if bundles.size == 0
        des_dir = resources_des_dir
        FileUtils.mkdir(des_dir) unless File.exist?(des_dir)
        bundles.map { |bundle| `cp -r #{bundle} #{des_dir}` }
      end

      # 拷贝resources/resource
      def copy_other_resources
        resources = other_resources
        return if resources.size == 0
        des_dir = resources_des_dir
        FileUtils.mkdir(des_dir) unless File.exist?(des_dir)
        resources.map { |res| `cp -r #{res} #{des_dir}` }
      end

      # 获取podspec中的resource_bundles
      def resource_bundles
        return [] if @file_accessors.nil?
        resource_bundles = @file_accessors.flat_map(&:resource_bundles)
        return [] if resource_bundles.nil? || resource_bundles.size == 0
        resource_bundles.compact.flat_map(&:keys).map { |key| "#{build_device_dir}/#{key}.bundle" }
      end

      # 获取podspec中resource/resources
      def other_resources
        return [] if @file_accessors.nil?
        resources = @file_accessors.flat_map(&:resources)
        return [] if resources.nil? || resources.size == 0
        resources.compact.reject { |res| reject_resource_ext.include?(res.extname) }.map(&:to_s)
      end

      # 需要排除的资源文件后缀
      def reject_resource_ext
        %w[.xcdatamodeld .xcdatamodel .xcmappingmodel .xib .storyboard]
      end

      # 合并静态库
      def merge_static_libs
        # 合并真机静态库
        merge_static_libs_for_device if @isRootSpec
        # 合并模拟器静态库
        merge_static_libs_for_sim if @isRootSpec
        # 合并真机和模拟器
        merge_device_sim
      end

      # 合并真机和模拟器
      def merge_device_sim
        libs = static_libs_in_sandbox + static_libs_in_sandbox(build_sim_dir)
        output = "#{build_device_dir}/#{framework_name}.framework/#{framework_name}"
        `lipo -create -output #{output} #{libs.join(' ')}` unless libs.empty?
      end

      # 合并真机静态库
      def merge_static_libs_for_device
        static_libs = static_libs_in_sandbox + vendored_static_libraries
        return if static_libs.empty?
        libs = ios_architectures.map do |arch|
          library = "#{build_device_dir}/package-#{framework_name}-#{arch}.a"
          `libtool -arch_only #{arch} -static -o #{library} #{static_libs.join(' ')}`
          library
        end
        output = "#{build_device_dir}/#{framework_name}.framework/#{framework_name}"
        `lipo -create -output #{output} #{libs.join(' ')}` if libs.size > 0
      end

      # 合并模拟器静态库
      def merge_static_libs_for_sim
        static_libs = static_libs_in_sandbox(build_sim_dir) + vendored_static_libraries
        return if static_libs.empty?
        libs = ios_architectures_sim.map do |arch|
          library = "#{build_sim_dir}/package-#{framework_name}-#{arch}.a"
          `libtool -arch_only #{arch} -static -o #{library} #{static_libs.join(' ')}`
          library
        end
        output = "#{build_sim_dir}/#{framework_name}.framework/#{framework_name}"
        `lipo -create -output #{output} #{libs.join(' ')}` if libs.size > 0
      end

      # 存放资源的目录
      def resources_des_dir
        "#{build_device_dir}/#{framework_name}.framework/resources"
      end

      # 存放动态库的目录
      def dynamic_libs_des_dir
        "#{build_device_dir}/#{framework_name}.framework/fwks"
      end

      # 存放vendored_libraries的目录
      def vendored_libraries_dir
        "#{build_device_dir}/#{framework_name}.framework/libs"
      end

      # 真机路径
      def build_device_dir
        'build-device'
      end

      # 模拟器路径
      def build_sim_dir
        'build-simulator'
      end

      # 获取vendored_libraries
      def vendored_libraries
        return [] if @file_accessors.nil?
        libs = @file_accessors.flat_map(&:vendored_libraries) || []
        libs.compact.map(&:to_s)
      end

      # 获取vendored_frameworks
      def vendored_frameworks
        return [] if @file_accessors.nil?
        fwks = @file_accessors.flat_map(&:vendored_frameworks) || []
        fwks.compact.map(&:to_s)
      end

      # 获取静态库
      def vendored_static_libraries
        return [] if @file_accessors.nil?
        file_accessors = @file_accessors
        # libs = file_accessors.flat_map(&:vendored_static_frameworks).map { |f| f + f.basename('.*') } || []
        # libs += file_accessors.flat_map(&:vendored_static_libraries)
        libs = file_accessors.flat_map(&:vendored_static_libraries) || []
        @vendored_static_libraries = libs.compact.map(&:to_s)
        @vendored_static_libraries
      end

      # 获取动态库
      def vendored_dynamic_libraries
        return [] if @file_accessors.nil?
        file_accessors = @file_accessors
        libs = file_accessors.flat_map(&:vendored_dynamic_frameworks) || []
        libs += file_accessors.flat_map(&:vendored_dynamic_libraries)
        @vendored_dynamic_libraries = libs.compact.map(&:to_s)
        @vendored_dynamic_libraries
      end

      # 获取xcframework
      def vendored_xcframeworks
        return [] if @file_accessors.nil?
        xcframeworks = @file_accessors.flat_map(&:vendored_xcframeworks) || []
        xcframeworks.compact.map(&:to_s)
      end

      # 获取静态库
      def static_libs_in_sandbox(build_dir = build_device_dir)
        Dir.glob("#{build_dir}/#{framework_name}.framework/#{framework_name}")
      end

      # 最终生成的framework的name
      # 先判断是否有module_name，再判断是否有header_dir，如果都没有，使用name
      def framework_name
        @spec.module_name
      end

      # 真机CPU架构
      def ios_architectures
        archs = %w[arm64]
        vendored_static_libraries.each do |library|
          archs = `lipo -info #{library}`.split & archs
        end
        archs
      end

      # 模拟器CPU架构
      def ios_architectures_sim
        archs = %w[x86_64]
        vendored_static_libraries.each do |library|
          archs = `lipo -info #{library}`.split & archs
        end
        archs
      end

      # 真机编译（只支持 arm64）
      def compile
        defines = "GCC_PREPROCESSOR_DEFINITIONS='$(inherited)' GCC_WARN_INHIBIT_ALL_WARNINGS=YES -quiet"
        # defines = "GCC_PREPROCESSOR_DEFINITIONS='$(inherited)' -quiet"
        unless @spec.consumer(@platform).compiler_flags.empty?
          defines += ' '
          defines += @spec.consumer(@platform).compiler_flags.join(' ')
        end

        options = "ARCHS=\'#{ios_architectures.join(' ')}\' OTHER_CFLAGS=\'-fembed-bitcode -Qunused-arguments\'"
        xcodebuild(defines, options, build_device_dir, @build_model)

        defines
      end

      # 模拟器编译（只支持 x86-64）
      def build_sim_libraries(defines)
        if @platform.name == :ios
          options = "-sdk iphonesimulator ARCHS=\'#{ios_architectures_sim.join(' ')}\'"
          xcodebuild(defines, options, build_sim_dir, @build_model)
        end
      end

      def target_name
        # 区分多平台，如配置了多平台，会带上平台的名字
        # 如libwebp-iOS
        if @spec.available_platforms.count > 1
          name = "#{@spec.name}-#{Platform.string_name(@spec.consumer(@platform).platform_name)}"
          return name if @installer && @installer.pod_targets.map { |pod| pod.name }.include?(name)
          @spec.name
        else
          @spec.name
        end
      end

      # 调用 xcodebuild 编译
      def xcodebuild(defines = '', args = '', build_dir = 'build', build_model = 'Release')
        unless File.exist?("Pods.xcodeproj") #cocoapods-generate v2.0.0
          command = "xcodebuild #{defines} #{args} CONFIGURATION_BUILD_DIR=#{File.join(File.expand_path("..", build_dir), File.basename(build_dir))} clean build -configuration #{build_model} -target #{target_name} -project ./Pods/Pods.xcodeproj"
        else
          command = "xcodebuild #{defines} #{args} CONFIGURATION_BUILD_DIR=#{build_dir} clean build -configuration #{build_model} -target #{target_name} -project ./Pods.xcodeproj"
        end

        UI.info "#{command}"
        output = `#{command}`.lines.to_a

        if $CHILD_STATUS.exitstatus != 0
          log_file = File.join(Dir.pwd, "build_error.log")
          error_msg = <<~EOF
            😈 可恶，编译失败了~ 😈
            请查看下面的报错信息或者打开 #{log_file} 查看
            编译命令:
                #{command}
            报错信息:
            #{output.map { |line| "   #{line}" }.join}
          EOF
          FileUtils.rm_f(log_file) if File.exist?(log_file)
          file = File.new(log_file, "w+")
          file.puts(error_msg)
          file.close

          raise Informative, error_msg

          Process.exit
        end
      end

      def framework
        @framework ||= begin
                         framework = Framework.new(framework_name, @platform.name.to_s)
                         framework.make
                         framework
                       end
      end

      # ---------- 以下方法无用 -------------

      def is_debug_model
        @build_model == "Debug"
      end

      def build_static_library_for_ios(output)
        static_libs = static_libs_in_sandbox('build') + static_libs_in_sandbox('build-simulator') + @vendored_libraries
        # if is_debug_model
        ios_architectures.map do |arch|
          static_libs += static_libs_in_sandbox("build-#{arch}") + @vendored_libraries
        end
        ios_architectures_sim do |arch|
          static_libs += static_libs_in_sandbox("build-#{arch}") + @vendored_libraries
        end
        # end

        build_path = Pathname("build")
        build_path.mkpath unless build_path.exist?

        # if is_debug_model
        libs = (ios_architectures + ios_architectures_sim) .map do |arch|
          # library = "build-#{arch}/lib#{target_name}.a"
          library = "build-#{arch}/#{target_name}.framework/#{target_name}"
          library
        end
        # else
        #   libs = ios_architectures.map do |arch|
        #     library = "build/package-#{@spec.name}-#{arch}.a"
        #     # libtool -arch_only arm64 -static -o build/package-armv64.a build/libIMYFoundation.a build-simulator/libIMYFoundation.a
        #     # 从liBFoundation.a 文件中，提取出 arm64 架构的文件，命名为build/package-armv64.a
        #     UI.message "libtool -arch_only #{arch} -static -o #{library} #{static_libs.join(' ')}"
        #     `libtool -arch_only #{arch} -static -o #{library} #{static_libs.join(' ')}`
        #     library
        #   end
        # end

        UI.message "lipo -create -output #{output} #{libs.join(' ')}"
        `lipo -create -output #{output} #{libs.join(' ')}`
      end

      def cp_to_source_dir
        framework_name = "#{@spec.name}.framework"
        target_dir = File.join(CBin::Config::Builder.instance.zip_dir,framework_name)
        FileUtils.rm_rf(target_dir) if File.exist?(target_dir)

        zip_dir = CBin::Config::Builder.instance.zip_dir
        FileUtils.mkdir_p(zip_dir) unless File.exist?(zip_dir)

        `cp -fa #{framework.root_path}/#{framework_name} #{target_dir}`
      end

      def copy_headers
        #走 podsepc中的public_headers
        public_headers = Array.new

        #by slj 如果没有头文件，去 "Headers/Public"拿
        # if public_headers.empty?
        spec_header_dir = "./Headers/Public/#{@spec.name}"
        unless File.exist?(spec_header_dir)
          spec_header_dir = "./Pods/Headers/Public/#{@spec.name}"
        end
        return unless File.exist?(spec_header_dir)
        # raise "copy_headers #{spec_header_dir} no exist " unless File.exist?(spec_header_dir)
        Dir.chdir(spec_header_dir) do
          headers = Dir.glob('*.h')
          headers.each do |h|
            public_headers << Pathname.new(File.join(Dir.pwd,h))
          end
        end
        # end

        # UI.message "Copying public headers #{public_headers.map(&:basename).map(&:to_s)}"

        public_headers.each do |h|
          `ditto #{h} #{framework.headers_path}/#{h.basename}`
        end

        # If custom 'module_map' is specified add it to the framework distribution
        # otherwise check if a header exists that is equal to 'spec.name', if so
        # create a default 'module_map' one using it.
        if !@spec.module_map.nil?
          module_map_file = @file_accessor.module_map
          if Pathname(module_map_file).exist?
            module_map = File.read(module_map_file)
          end
        elsif public_headers.map(&:basename).map(&:to_s).include?("#{@spec.name}.h")
          module_map = <<-MAP
          framework module #{@spec.name} {
            umbrella header "#{@spec.name}.h"

            export *
            module * { export * }
          }
          MAP
        end

        unless module_map.nil?
          UI.message "Writing module map #{module_map}"
          unless framework.module_map_path.exist?
            framework.module_map_path.mkpath
          end
          File.write("#{framework.module_map_path}/module.modulemap", module_map)
        end
      end

      def copy_license
        UI.section "Copying license #{@spec}" do
          license_file = @spec.license[:file] || 'LICENSE'
          `cp "#{license_file}" .` if Pathname(license_file).exist?
        end
      end

      # def copy_resources
      #   UI.section "copy_resources #{@spec}" do
      #     resource_dir = './build/*.bundle'
      #     resource_dir = './build-armv7/*.bundle' if File.exist?('./build-armv7')
      #     resource_dir = './build-arm64/*.bundle' if File.exist?('./build-arm64')
      #
      #     bundles = Dir.glob(resource_dir)
      #
      #     bundle_names = [@spec, *@spec.recursive_subspecs].flat_map do |spec|
      #       consumer = spec.consumer(@platform)
      #       consumer.resource_bundles.keys +
      #         consumer.resources.map do |r|
      #           File.basename(r, '.bundle') if File.extname(r) == 'bundle'
      #         end
      #     end.compact.uniq
      #
      #     bundles.select! do |bundle|
      #       bundle_name = File.basename(bundle, '.bundle')
      #       bundle_names.include?(bundle_name)
      #     end
      #
      #     if bundles.count > 0
      #       UI.message "Copying bundle files #{bundles}"
      #       bundle_files = bundles.join(' ')
      #       `cp -rp #{bundle_files} #{framework.resources_path} 2>&1`
      #     end
      #
      #     real_source_dir = @source_dir
      #     unless @isRootSpec
      #       spec_source_dir = File.join(Dir.pwd,"#{@spec.name}")
      #       unless File.exist?(spec_source_dir)
      #         spec_source_dir = File.join(Dir.pwd,"Pods/#{@spec.name}")
      #       end
      #       raise "copy_resources #{spec_source_dir} no exist " unless File.exist?(spec_source_dir)
      #
      #       real_source_dir = spec_source_dir
      #     end
      #     resources = [@spec, *@spec.recursive_subspecs].flat_map do |spec|
      #       expand_paths(real_source_dir, spec.consumer(@platform).resources)
      #     end.compact.uniq
      #
      #     if resources.count == 0 && bundles.count == 0
      #       framework.delete_resources
      #       return
      #     end
      #
      #     if resources.count > 0
      #       #把 路径转义。 避免空格情况下拷贝失败
      #       escape_resource = []
      #       resources.each do |source|
      #         escape_resource << Shellwords.join(source)
      #       end
      #       UI.message "Copying resources #{escape_resource}"
      #       `cp -rp #{escape_resource.join(' ')} #{framework.resources_path}`
      #     end
      #   end
      # end

      def expand_paths(source_dir, path_specs)
        path_specs.map do |path_spec|
          Dir.glob(File.join(source_dir, path_spec))
        end
      end
    end
  end
end
