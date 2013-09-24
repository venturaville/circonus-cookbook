include CirconusApiMixin

def load_current_resource
  if @new_resource.current_resource_ref then
    return @new_resource.current_resource_ref
  end

  @current_resource = Chef::Resource::CirconusWorksheet.new(new_resource.name)
  @new_resource.current_resource_ref(@current_resource) # Needed for graphs to link to 

  # If ID was provided, copy it into the existing resource
  @current_resource.id(@new_resource.id)

  # If we are in fact disabled, return now
  unless (node['circonus']['enabled']) then
    return @current_resource
  end

  if @current_resource.id then
    # We claim the worksheet already exists
    begin
      payload = api.get_worksheet(@current_resource.id)
    rescue RestClient::ResourceNotFound
      raise Chef::Exceptions::ConfigurationError, "Circonus worksheet ID #{@current_resource.id} does not appear to exist.  Don't specify the ID if you are trying to create it."
    end

    @current_resource.payload(payload)
    @current_resource.exists(true)
  else
    # Don't know if the worksheet exists or not - look for it by title
    ids = api.find_worksheet_ids(@new_resource.title)

    unless (ids.empty?) then 
      unless (ids.length == 1) then 
        # uh-oh
        raise Chef::Exceptions::ConfigurationError, "More than one circonus worksheet exists with title '#{new_resource.title}' - saw #{ids.join(', ')} .  You need to specify which ID you are referring to."
      end
      # Found it - set the ID on the worksheet resource
      @current_resource.id(ids[0])
      @current_resource.payload(api.get_worksheet(@current_resource.id()))
      @current_resource.exists(true)
    end
  end

  # If the worksheet currently exists, then copy in to the new resource.
  if @current_resource.exists then
    # Deep clone
    @new_resource.payload(Marshal.load(Marshal.dump(@current_resource.payload)))
    @new_resource.id(@current_resource.id)
    @new_resource.exists(true)
  else 
    init_empty_payload
  end

  copy_resource_attributes_into_payload

  @current_resource
end

def init_empty_payload
  payload = {
    'graphs' => []
  }
  @new_resource.payload(payload)
end

def copy_resource_attributes_into_payload

  p = @new_resource.payload

  # These are all strings
  [
   'title',
  ].each do |field|
    value = @new_resource.method(field).call
    unless value.nil? then
      @new_resource.payload[field] = value.to_s
    end
  end

  # Graphs gets populated by circonus_worksheet_graph resources

  # Tags is an array
  @new_resource.payload['tags'] = @new_resource.tags()
  
end

def any_payload_changes?
  changed = false

  # We don't look at worksheet_graphs, because when a graph changes, it sends
  # an upload action notification to us anyway

  # These can all legitimately change, and are all strings

  [
   'title',
  ].each do |field|
    old = @current_resource.payload[field].to_s
    new = @new_resource.payload[field].to_s
    this_changed = old != new
    if this_changed then
      Chef::Log.debug("CCD: Circonus worksheet '#{@new_resource.name} shows field #{field} changed from '#{old}' to '#{new}'")
    end
    changed ||= this_changed
  end

  # Tags is an array of strings - sort and stringify first!
  @current_resource.payload['tags'] ||= []
  @current_resource.payload['tags'] = @current_resource.payload['tags'].map { |t| t.to_s }.sort
  @new_resource.payload['tags'] = @new_resource.payload['tags'].map { |t| t.to_s }.sort
  if @current_resource.payload['tags'] != @new_resource.payload['tags']
    Chef::Log.debug("CCD: Circonus worksheet '#{@new_resource.name} shows field tags changed from '#{@current_resource.payload['tags'].join(',')}' to '#{@new_resource.payload['tags'].join(',')}'")
    changed = true
  end

  return changed

end

def action_create
  # If we are in fact disabled, return now
  unless (node['circonus']['enabled']) then
    Chef::Log.info("Doing nothing for circonus_worksheet[#{@current_resource.name}] because node[:circonus][:enabled] is false")
    return
  end

  unless @current_resource.exists then
    @new_resource.updated_by_last_action(true)
    @new_resource.notifies(:upload, @new_resource, :delayed)
    return
  end

  if any_payload_changes? then
    @new_resource.updated_by_last_action(true)
    @new_resource.notifies(:upload, @new_resource, :delayed)
    return    
  end

end

def action_upload

  unless (node['circonus']['enabled']) then
    Chef::Log.info("Doing nothing for circonus_worksheet[#{@current_resource.name}] because node[:circonus][:enabled] is false")
    return
  end

  # At this point we assume @new_resource.payload is correct
  Chef::Log.debug("About to upload worksheet, have payload:\n" + JSON.pretty_generate(@new_resource.payload))

  if @new_resource.exists then
    Chef::Log.info("Circonus worksheet upload: EDIT mode, id " + @new_resource.id)
    api.edit_worksheet(@new_resource.id, @new_resource.payload)
  else
    Chef::Log.info("Circonus worksheet upload: CREATE mode")
    api.create_worksheet(@new_resource.payload)
  end
  @new_resource.updated_by_last_action(true)
end

