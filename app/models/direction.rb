class Direction 
    include ActiveModel::Model

    attr_accessor :origin, :destination

    def initialize(addresses_hash)
        @origin = addresses_hash['origin'] 
        @destination = addresses_hash['destination'] 
    end

    def fetch_directions 

        response = Faraday.get "https://maps.googleapis.com/maps/api/directions/json?origin=#{@origin}&destination=#{@destination}key={ENV[google_directions_key]}"

    
        @directions = JSON.parse(response.body)
        
        if @directions['status'] == 'OK'
            parse_steps

        else
            {status: @directions['status']}
        end
        
    end

    private

    def parse_steps
        leg = @directions['routes'][0]['legs'][0]

        steps = leg['steps'].map do |step|
            step['html_instructions']
        end


        {distance: leg['distance']['text'], duration: leg['duration']['text'], steps: steps, destination: leg['end_address'],  origin: leg['start_address'], status: @directions['status']}

    end

end

