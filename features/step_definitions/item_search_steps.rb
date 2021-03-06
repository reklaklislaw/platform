When /^I search for "(.*?)"( in the "(.*?)" field)?$/ do |keyword, junk, query_field|
  @resource = 'item'
  @query_field = query_field || 'q'
  @query_string = keyword
  @params.merge!({ @query_field => @query_string })
end

When /^I search the "(.*?)" field for records with a date between "(.*?)" and "(.*?)"$/ do |field, start_date, end_date|
  @resource = 'item'

  @params.merge!({
    "#{field}.after" => start_date,
    "#{field}.before" => end_date,
  })
end

When /^I search the "(.*?)" field for records with a date (before|after) "(.*?)"$/ do |field, modifier, target_date|
  @resource = 'item'
  @params.merge!({ "#{field}.#{modifier}" => target_date })
end

Then /^the API should return no records$/ do
  json = item_query_to_json(@params)
  expect(json.size).to eq 0
end

Then /^the API should not return record (.+)$/ do |id|
  json = item_query_to_json(@params)
  expect( json.any? {|doc| doc['_id'] == id } ).to be_false
end

