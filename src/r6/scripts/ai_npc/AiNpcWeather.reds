// The sky, as one word for the prompt.
//
// A state read when the prompt is built, not an event: nothing to schedule, nothing to miss
// while the phone is closed. Weather is global in this game, so it is the one piece of world
// state a character knows without being told where V is.
//
// Measured over 200 runs across four conditions: the action command survives untouched (40%
// in all four), no reply ever claims where V is, and only a character who has to travel
// comments on it -- 5/10 on a sandstorm, 1/10 on rain, 0/10 on clear. The salience comes from
// the weather itself, so nothing here asks for it.

module AiNpc

// The engine's weather state names, mapped to the vocabulary a model reads. Anything unknown
// -- a weather mod's own state -- falls back on the rain intensity, which is always defined.
func AiNpcWeatherWord(state: CName, rain: worldRainIntensity) -> String {
    switch state {
        case n"24h_weather_sandstorm":
            return "sandstorm";
        case n"24h_weather_toxic_rain":
            return "toxic rain";
        case n"24h_weather_storm":
            return "storm";
        case n"24h_weather_downpour":
            return "heavy rain";
        case n"24h_weather_rain":
            return "rain";
        case n"24h_weather_light_rain":
            return "light rain";
        case n"24h_weather_distant_rain":
            return "rain in the distance";
        case n"24h_weather_drizzle":
        case n"24h_weather_drizzle_light":
        case n"24h_weather_drizzle_heavy":
            return "drizzle";
        case n"24h_weather_fog":
        case n"24h_weather_fog_dense":
        case n"24h_weather_fog_dark_dense":
        case n"24h_weather_fog_heavy":
        case n"24h_weather_fog_wet":
        case n"24h_weather_mist":
            return "fog";
        case n"24h_weather_fog_rain":
        case n"24h_weather_haze_rain":
            return "rain and fog";
        case n"24h_weather_smog":
        case n"24h_weather_haze_smog":
        case n"24h_weather_pollution":
        case n"24h_weather_haze_pollution":
            return "smog";
        case n"24h_weather_haze":
        case n"24h_weather_haze_heavy":
            return "haze";
        case n"24h_weather_arid":
        case n"24h_weather_drought":
            return "dry heat";
        case n"24h_weather_humid":
        case n"24h_weather_muggy":
        case n"24h_weather_dew":
            return "humid";
        case n"24h_weather_windy":
        case n"24h_weather_sunny_windy":
            return "wind";
        case n"24h_weather_overcast":
        case n"24h_weather_overcast_broken":
        case n"24h_weather_overcast_light":
        case n"24h_weather_gloomy":
        case n"24h_weather_heavy_clouds":
        case n"24h_weather_heavy_clouds_dense":
            return "overcast";
        case n"24h_weather_cloudy":
        case n"24h_weather_light_clouds":
        case n"24h_weather_courier_clouds":
            return "cloudy";
        case n"24h_weather_clear":
        case n"24h_weather_sunny":
        case n"24h_weather_sunny_sunset":
            return "clear";
        default:
            return AiNpcRainWord(rain);
    }
}

func AiNpcRainWord(rain: worldRainIntensity) -> String {
    if Equals(rain, worldRainIntensity.HeavyRain) {
        return "heavy rain";
    }
    if Equals(rain, worldRainIntensity.LightRain) {
        return "rain";
    }
    return "clear";
}

// One line for <now>, terminated here like every other contributor to that section.
func AiNpcWeatherLine() -> String {
    let weather = GameInstance.GetWeatherSystem(GetGameInstance());
    if !IsDefined(weather) {
        return "";
    }

    let rain = weather.GetRainIntensityType();
    let state = weather.GetWeatherState();
    if !IsDefined(state) {
        return "CURRENT WEATHER: " + AiNpcRainWord(rain) + "\n";
    }

    return "CURRENT WEATHER: " + AiNpcWeatherWord(state.name, rain) + "\n";
}
