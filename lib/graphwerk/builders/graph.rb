# typed: strict
# frozen_string_literal: true

module Graphwerk
  module Builders
    class Graph
      extend T::Sig

      OptionsShape = T.type_alias {
        {
          layout: Graphwerk::Layout,
          deprecated_references_color: String,
          package_todo_color: String,
          application: T::Hash[Symbol, Object],
          graph: T::Hash[Symbol, Object],
          cluster: T::Hash[Symbol, Object],
          node: T::Hash[Symbol, Object],
          edge: T::Hash[Symbol, Object]
        }
      }

      DEFAULT_OPTIONS = T.let({
        layout: Graphwerk::Layout::Dot,
        deprecated_references_color: 'red',
        package_todo_color: 'red',
        application: {
          style: 'filled',
          fillcolor: '#333333',
          fontcolor: 'white'
        },
        graph: {
          root: Constants::ROOT_PACKAGE_NAME,
          overlap: false,
          splines: true
        },
        cluster: {
          color: 'blue'
        },
        node: {
          shape: 'box',
          style: 'rounded, filled',
          fontcolor: 'white',
          fillcolor: '#EF673E',
          color: '#EF673E',
          fontname: 'Lato'
        },
        edge: {
          len: '0.4'
        }
      }, OptionsShape)

      sig { params(package_set: Packwerk::PackageSet, options: T::Hash[Symbol, Object], root_path: Pathname).void }
      def initialize(package_set, options: {}, root_path: Pathname.new(ENV['PWD']))
        @package_set = package_set
        @options = T.let(DEFAULT_OPTIONS.deep_merge(options), OptionsShape)
        @root_path = root_path
        @graph = T.let(build_empty_graph, GraphViz)
        @nodes = T.let(build_empty_nodes, T::Hash[String, GraphViz::Node])
      end

      sig { returns(GraphViz) }
      def build
        setup_graph
        add_packages_to_graph
        add_package_dependencies_to_graph
        @graph
      end

      private

      sig { returns(GraphViz) }
      def build_empty_graph
        GraphViz.new(:strict, type: :digraph, use: @options[:layout].serialize)
      end

      sig { returns(T::Hash[String, GraphViz::Node]) }
      def build_empty_nodes
        {
          application: @graph.add_nodes(
            Constants::ROOT_PACKAGE_NAME,
            **@options[:application]
          )
        }
      end

      sig { void }
      def setup_graph
        @graph = build_empty_graph
        @graph['compound'] = true
        @nodes = build_empty_nodes
        @options[:graph].each_pair { |k,v| @graph.graph[k] =v }
        @options[:node].each_pair { |k,v| @graph.node[k] =v }
        @options[:edge].each_pair { |k,v| @graph.edge[k] =v }
      end

      sig { void }
      def add_package_dependencies_to_graph
        packages.each do |package|
          draw_dependencies(package)
          draw_deprecated_references(package)
          draw_package_todos(package)
        end
      end

      sig { void }
      def add_packages_to_graph
        packages.each do |package|
          cluster = cluster_for(package.name)
          @nodes[package.name] = cluster.add_nodes(package.name, color: package.color, label: package.name.split('/').last)
        end
      end

      sig { params(package_name: String).returns(GraphViz) }
      def cluster_for(package_name)
        parts = package_name.split('/')
        package_name = parts.pop
        cluster_name = parts.join('/')
        if cluster_name.empty?
          @graph
        else
          cluster = @graph.get_graph("cluster_#{cluster_name}")
          if cluster.nil?
            cluster = @graph.add_graph("cluster_#{cluster_name}", @options[:cluster].merge(label: cluster_name))
          end
          cluster
        end
      end

      sig { params(package: Presenters::Package).void }
      def draw_dependencies(package)
        package.dependencies.each do |dependency|
          unless @nodes[dependency]
            abort "Unable to add edge `#{package.name}`->`#{dependency}`"
          end
          add_edge(package.name, dependency, package.color)
        end
      end

      sig { params(package: Presenters::Package).void }
      def draw_deprecated_references(package)
        package.deprecated_references.each do |reference|
          add_edge(package.name, reference, @options[:deprecated_references_color])
        end
      end

      sig { params(package: Presenters::Package).void }
      def draw_package_todos(package)
        package.package_todos.each do |todo|
          add_edge(package.name, todo, @options[:package_todo_color])
        end
      end

      sig { params(from: String, to: String, color: String).void }
      def add_edge(from, to, color)
        source_cluster_name = cluster_for(from)&.name || from
        destination_cluster_name = cluster_for(to)&.name || to
        options = { color: color }
        unless source_cluster_name == destination_cluster_name
          options[:ltail] = source_cluster_name unless source_cluster_name == 'strict'
          options[:lhead] = destination_cluster_name unless destination_cluster_name == 'strict'
        end
        @graph.add_edges(@nodes[from], @nodes[to], options)
      end

      sig { returns(T::Array[Presenters::Package]) }
      def packages
        @packages = T.let(@packages, T.nilable(T::Array[Presenters::Package]))
        @packages ||= @package_set.map { |package| Presenters::Package.new(package, @root_path) }
      end
    end
  end
end
