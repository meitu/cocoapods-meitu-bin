
module Pod
  class Command
    class Bin < Command
      class Lock < Bin
        class Version < Lock
          include Pod

          self.summary = '分析项目中使用的`Pod`库版本'

          self.arguments = [
            CLAide::Argument.new('POD_NAME', true)
          ]

          def self.options
            [
              %w[--source 查看二进制对应源码版本]
            ].concat(super).uniq
          end

          def initialize(argv)
            super
            @pod_name = argv.shift_argument
            @source = argv.flag?('source', false)
          end

          def run
            super
            raise Informative, "请输入Pod库名称，如：AFNetworking" if @pod_name.nil?
            versions = []
            @analyze_result.specifications.map do |spec|
              if spec.name == @pod_name
                versions << spec.version
              end
            end
            versions = versions.uniq
            UI.puts "\n"
            raise Informative, "未查找到`#{@pod_name}`的版本号，请检查`#{@pod_name}`是否拼写错误" if versions.empty?
            UI.puts "`#{@pod_name}`版本号如下：".yellow
            versions.map do |v|
              if @source
                UI.puts "- #{get_source_version(v.to_s)}"
              else
                UI.puts "- #{v}"
              end
            end

            UI.puts "[!] `#{@pod_name}`有`#{versions.size}`个版本，可能会导致意想不到的事情，请确保每个Pod库只有一个依赖版本".yellow if versions.size > 1
          end

          private

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

        end
      end
    end
  end
end
