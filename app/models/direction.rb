require 'google_maps_service/polyline'

class Direction 
    include ActiveModel::Model
    attr_accessor :origin, :destination

    def initialize(addresses_hash)
        @origin = addresses_hash['origin'] 
        @destination = addresses_hash['destination']
    end

    def fetch_directions 

        response = Faraday.get "https://maps.googleapis.com/maps/api/directions/json?origin=#{@origin}&destination=#{@destination}&key=#{ENV['GOOGLE_DIRECTIONS_KEY']}&units=metric"


        directions = JSON.parse(response.body)

        if directions['status'] == 'OK'
            data = divide_polylines_and_parse_directions(directions['routes'][0])
            data['directions_status'] = directions['status']
            data
        else
            {directions_status: directions['status']}
        end
        
    end



    private

    def get_polyline_color weather_id 
        if  (weather_id  < 300 )
            #thunderstorm
            '#910136'
        elsif (weather_id < 400)
            #dirzzle
            '#016b91'
        elsif (weather_id < 600)
            #rain
            '#140191'
        elsif (weather_id  < 700) 
            #snow
            '#912f01'
        else 
            #clear
            '#40a601'
        end
    end

    def split_points_to_100km(points, polyline_distance_counter, remaining_points_from_previous_polyline)
        points_distance_counter = 0
        one_hundered_km_points = []
        previous_index = 0
        (points.length - 1).times do |current_index|
            points_distance_counter += SphericalUtil.computeDistanceBetween(points[current_index], points[current_index + 1])
            if points_distance_counter + polyline_distance_counter >= 100000
                one_hundered_km_points << {points: points[previous_index..current_index + 1], distance: points_distance_counter + polyline_distance_counter}
                previous_index = current_index + 1
                points_distance_counter = 0
                polyline_distance_counter = 0
            end
        end
        one_hundered_km_points[0][:points] = remaining_points_from_previous_polyline + one_hundered_km_points[0][:points]
        {divided_points: one_hundered_km_points, remaining_km: points_distance_counter, remaining_points: points[previous_index..-1]}
    end

    def construct_encoded_polyline_with_color(decoded_polyline, weather_id)
        {points: GoogleMapsService::Polyline.encode(decoded_polyline), color: get_polyline_color(weather_id)}
    end

    def update_weather_conditions_distance(weather_report, distance, weather_conditions)
        new_weather_conditions = weather_conditions.clone
        if new_weather_conditions[weather_report['main']].nil?
            new_weather_conditions[weather_report['main']] = 0
        end
        distance_in_km = (distance * 0.001).floor
        new_weather_conditions[weather_report['main']] += distance_in_km
        new_weather_conditions

    end

    def divide_polylines_and_parse_directions(route)
        polyline_distance_counter = 0
        points_temp_bucket = []
        divided_polylines = []
        directions = []
        weather_conditions_distance = {}
        leg = route['legs'][0]
        leg['steps'].each do |step|
            polyline_distance = step['distance']['value']
            points = GoogleMapsService::Polyline.decode(step['polyline']['points'])
            if polyline_distance + polyline_distance_counter >= 100000
                divided_points_with_counter = split_points_to_100km(points, polyline_distance_counter, points_temp_bucket.flatten)
                one_hundered_km_points = divided_points_with_counter[:divided_points]
                
                one_hundered_km_points.each do |one_hundered_km|
                    weather_report = get_weather(one_hundered_km[:points][0])
                    weather_conditions_distance = update_weather_conditions_distance(weather_report, one_hundered_km[:distance] , weather_conditions_distance )
                    divided_polylines << construct_encoded_polyline_with_color(one_hundered_km[:points], weather_report['id'])
                end

                points_temp_bucket = divided_points_with_counter[:remaining_points] 
                polyline_distance_counter = divided_points_with_counter[:remaining_km]
            else
              points_temp_bucket << points
              polyline_distance_counter += polyline_distance
            end
            directions << {html_instructions: step['html_instructions'], duration: step['duration']['text']}
        end
        destination_weather = get_weather(points_temp_bucket[-1][-1])
        weather_conditions_distance = update_weather_conditions_distance(destination_weather, polyline_distance_counter, weather_conditions_distance)
        divided_polylines << construct_encoded_polyline_with_color(points_temp_bucket.flatten, destination_weather['id'])

        
        { directions: {distance: leg['distance']['text'], duration: leg['duration']['text'], steps: directions, destination: leg['end_address'],  origin: leg['start_address'] }, mapData: { polylines: divided_polylines, bounds: route['bounds'], start_location: leg['start_location'], end_location: leg['end_location']}, weather_conditions: weather_conditions_distance}
    end

    def get_weather(coordinates)
        stringify_coordinates = coordinates.stringify_keys
        response = Faraday.get("https://api.openweathermap.org/data/2.5/weather?lat=#{stringify_coordinates['lat']}&lon=#{stringify_coordinates['lng']}&APPID=#{ENV['WEATHER_API_KEY']}&units=metric")
        weather = JSON.parse(response.body)  
        weather['weather'][0]
    end

end

