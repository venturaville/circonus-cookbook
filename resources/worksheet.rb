actions :create, :upload #, :delete # TODO

# graphs are represented by circonus_worksheet_graph resource
attribute :title, :kind_of => String, :name_attribute => true
attribute :id
attribute :tags, :kind_of => Array, :default => []

# These are undocumented, but appear in the get_worksheet API call response
# notes
# description

attribute :exists, :kind_of => [TrueClass, FalseClass], :default => false
attribute :payload
attribute :current_resource_ref


def initialize(*args)
  super
  @action = :create  # default_action pre 0.10.10
end
