include CirconusApiMixin

# Chef child of both worksheet and metric

def load_current_resource

  if @new_resource.current_resource_ref then
    return @new_resource.current_resource_ref
  end
  
  @current_resource = Chef::Resource::CirconusWorksheetWorksheet.new(new_resource.name)
  @new_resource.current_resource_ref(@current_resource)

  # If we are in fact disabled, return now
  unless (node['circonus']['enabled']) then
    return @current_resource
  end

  # Verify that the referenced worksheet resource exists
  new_worksheet_resource = run_context.resource_collection.find(:circonus_worksheet => @new_resource.worksheet)

  unless new_worksheet_resource then
    raise Chef::Exceptions::ConfigurationError, "Circonus worksheet_graph #{@new_resource.name} references worksheet #{@new_resource.worksheet}, which must exist as a resource (it doesn't)."
  end

  @current_resource.type(@new_resource.type)
  @current_resource.data_formula(@new_resource.data_formula)

  # OK, set worksheet backlinks
  @new_resource.worksheet_resource(new_worksheet_resource)
  current_worksheet_resource = new_worksheet_resource.current_resource_ref
  @current_resource.worksheet_resource(current_worksheet_resource)

  if @new_resource.graph? then
    # Verify that the referenced metric exists
    new_metric_resource = run_context.resource_collection.find(:circonus_metric => @new_resource.metric)

    unless new_metric_resource then
      raise Chef::Exceptions::ConfigurationError, "Circonus worksheet graph #{@new_resource.name} references metric #{@new_resource.metric}, which must exist as a resource (it doesn't)."
    end

    # OK, set metric backlinks
    @new_resource.metric_resource(new_metric_resource)
    current_metric_resource = new_metric_resource.current_resource_ref
    @current_resource.metric_resource(current_metric_resource)

    # Copy non volatile fields in 
    @current_resource.broker(@new_resource.broker)
    @current_resource.metric(@new_resource.metric)
  end

  # Check to see if the graph exists in the payload of the current (prior state) worksheet
  if current_resource_dependencies_exist? then

    @current_resource.graph_id(@current_resource.title)

    index = match_index
    Chef::Log.debug("In worksheet_graph.LCR, have match idx " + index.inspect())
    unless index.nil? then
      @current_resource.exists(true)
      @current_resource.index_in_worksheet_payload(match_index)
    end
  else
    @current_resource.exists(false)
  end

  # If the graph currently exists, tell the desired state about it
  if @current_resource.exists then
    @new_resource.exists(true)
    @new_resource.index_in_worksheet_payload(@current_resource.index_in_worksheet_payload)
    @new_resource.check_id(@current_resource.check_id)
  end

  @current_resource

end

def any_payload_changes?
  # We can assume we exist, and have a payload index on the worksheet
  old_payload = @current_resource.worksheet_payload[@current_resource.index_in_worksheet_payload]
  new_payload = @new_resource.to_payload_hash

  # Assume check_id, metric_name, and metric_type match

  # Treat color special by allowing the server to set a default.
  new_payload['color'] ||= old_payload['color']

  # Treat alpha special by allowing the server to set a default.
  new_payload['alpha'] ||= old_payload['alpha']
  # However, server has a bug; may set alpha to invalid value null.  Check and fix.
  new_payload['alpha'] = new_payload['alpha'].nil? ? 0.3 : new_payload['alpha']
  fields = @new_resource.payload_fields

  changed = false
  fields.each do | field |
    old = old_payload[field].to_s
    new = new_payload[field].to_s
    this_changed = old != new
    if this_changed then
      Chef::Log.debug("CCD: Circonus worksheet graph '#{@new_resource.name} shows field #{field} changed from '#{old}' to '#{new}'")
    end
    changed ||= this_changed
  end

  return changed
end

def action_create
  # If we are in fact disabled, return now
  unless (node['circonus']['enabled']) then
    Chef::Log.info("Doing nothing for circonus_worksheet[#{@current_resource.name}] because node[:circonus][:enabled] is false")
    return
  end

  if @current_resource.exists && any_payload_changes? then

    # REPLACE myself in my worksheet's graphs payload
    @new_resource.worksheet_payload[@new_resource.index_in_worksheet_payload] = @new_resource.to_payload_hash()
    @new_resource.updated_by_last_action(true)

  elsif !@current_resource.exists
    # NOTE - we may not have a check_id yet!  Rely on the the worksheet's :upload action to populate that if needed (since by that point, the metric (and thus the check ID) should exist)
    # Grotesquely, do so using a hack in the check_id field of the payload

    # APPEND myself into my worksheet's graphs payload
    @new_resource.worksheet_payload << @new_resource.to_payload_hash()
    @new_resource.updated_by_last_action(true)
  end

  if (@new_resource.updated_by_last_action?) then
    # Inform the worksheet that yes we will need to do an upload
    @new_resource.notifies(:upload, @new_resource.worksheet_resource, :delayed)    
  end

end

def match_index
  # OK, we know we have a payload.  Are we in there as a worksheet_graph?
  @match_index ||= @current_resource.worksheet_payload.find_index do |graph|

    Chef::Log.debug("Examining existing graph: " + graph.inspect())
    Chef::Log.debug("Examining current check id: " + @current_resource.check_id.inspect())

    # Careful here.  We want to find any existing graph that matches on our identity fields.
    # Which would be the check_id and metric name.  Note that unlike rules and metrics, we do NOT compare on all fields - here, we only compare on our identity fields
    matched = true
    matched &&= graph['check_id'].to_s == @current_resource.check_id.to_s
    Chef::Log.debug("Check IDs appear to match? #{matched}")
    if @new_resource.graph? then
      # Chef resource name is @current_resource.metric
      # We need the circonus metric name
      circonus_metric_name = @current_resource.metric_resource.metric_name
      Chef::Log.debug("Have my metric name as: #{circonus_metric_name}")
      matched &&= graph['metric_name'] == circonus_metric_name
      Chef::Log.debug("Metric names appear to match? #{matched}")
    else
      matched &&= graph['data_formula'] == @current_resource.data_formula
    end
    Chef::Log.debug("Matched? " + matched.inspect())
    matched
  end
end

def current_resource_dependencies_exist?
  @current_resource.worksheet_resource.exists && (!@current_resource.graph? || @current_resource.metric_resource.exists)
end
