
module Pod
  class Command
    class Bin < Command
      class Lock < Bin
        class SpecRepo < Lock
          include Pod

          self.summary = '分析`podspec`源'
          self.description = <<-DESC
#{self.summary}，如果加`POD_NAME`，则分析该`POD_NAME`所属的repo仓库；如果不加，则打印项目中用到的repo仓库及每个仓库下Pod个数
          DESC

          self.arguments = [
            CLAide::Argument.new('POD_NAME', false)
          ]

          def initialize(argv)
            super
            @pod_name = argv.shift_argument
          end

          def run
            super
            if @pod_name.nil?
              spec_repo_summary
            else
              pod_source
            end
          end

          private

          def spec_repos
            raise Informative, "依赖分析失败" if @analyze_result.nil?
            result = Hash.new
            @analyze_result.specs_by_source.map do |source, specs|
              next unless source
              next if specs.empty?
              key = source.url || source.name

              # save `trunk` as 'trunk' so that the URL itself can be changed without lockfile churn
              key = Pod::TrunkSource::TRUNK_REPO_NAME if source.name == Pod::TrunkSource::TRUNK_REPO_NAME

              value = specs.map { |s| s.root.name }.uniq
              # 合并重复的source源，而不是替换
              if result[key].nil?
                result[key] = YAMLHelper.sorted_array(value)
              else
                result[key] = YAMLHelper.sorted_array(result[key].concat(value))
              end
            end
            result.compact
          end

          def external_sources
            deps = config.podfile.dependencies.select(&:external?)
            deps = deps.sort { |d, other| d.name <=> other.name }
            sources = {}
            deps.each { |d| sources[d.root_name] = d.external_source }
            sources
          end

          # 打印所有source及其pods个数
          def spec_repo_summary
            pod_count = 0
            UI.puts "\n"
            spec_repos.map do |source, specs|
              pod_count += specs.size
              UI.puts "#{source}".yellow
              UI.puts "- #{specs.size} pods"
            end
            pod_count += external_sources.keys.size
            UI.puts "External".yellow
            UI.puts "- #{external_sources.keys.size} pods"

            UI.puts "\n"
            UI.puts "total #{spec_repos.size + 1} sources, #{pod_count} pods".green
          end

          # 打印pod所属的source
          def pod_source
            sources = []
            external = false
            spec_repos.map do |source, specs|
              if specs.include?(@pod_name)
                sources << source
              end
            end
            external_sources.map do |pod, ext_source|
              if pod == @pod_name
                external = true
                sources << ext_source
              end
            end
            UI.puts "\n"
            raise Informative, "未找到`#{@pod_name}`所属的source，请检查`#{@pod_name}`是否拼写错误" if sources.empty?
            UI.puts "#{@pod_name}#{external ? ' (External Source)' : ''}".yellow
            sources.map { |source| UI.puts "- #{source}" }
          end
        end
      end
    end
  end
end
