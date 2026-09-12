#include "RadioFilter.hpp"

#include <cmath>
#include <cstring>

namespace ainpc::radio
{
namespace
{
constexpr double kPi = 3.14159265358979323846;

// Les deux sections d'un Butterworth d'ordre 4.
constexpr double kButterworthQ[2] = {0.54119610, 1.30656296};

struct Band
{
    double highPassHz;
    double lowPassHz;
    double drive; // zero : aucune saturation
};

Band BandOf(Level aLevel)
{
    switch (aLevel)
    {
    case Level::Light:
        return {200.0, 5000.0, 0.0};
    case Level::Strong:
        return {450.0, 2800.0, 3.0};
    case Level::Medium:
    default:
        return {300.0, 3400.0, 1.5};
    }
}
} // namespace

Level LevelNamed(const std::string& aName)
{
    if (aName == "off")
    {
        return Level::Off;
    }
    if (aName == "light")
    {
        return Level::Light;
    }
    if (aName == "strong")
    {
        return Level::Strong;
    }
    return Level::Medium;
}

const char* NameOf(Level aLevel)
{
    switch (aLevel)
    {
    case Level::Off:
        return "off";
    case Level::Light:
        return "light";
    case Level::Strong:
        return "strong";
    case Level::Medium:
    default:
        return "medium";
    }
}

double Filter::Biquad::Step(double aInput)
{
    const double output = b0 * aInput + z1;
    z1 = b1 * aInput - a1 * output + z2;
    z2 = b2 * aInput - a2 * output;
    return output;
}

Filter::Filter(Level aLevel, uint32_t aSampleRate)
{
    if (aLevel == Level::Off || aSampleRate == 0)
    {
        return;
    }
    const Band band = BandOf(aLevel);
    m_drive = band.drive;

    const double nyquistGuard = 0.45 * aSampleRate;
    const double lowPassHz = band.lowPassHz < nyquistGuard ? band.lowPassHz : nyquistGuard;

    for (const double q : kButterworthQ)
    {
        for (const bool highPass : {true, false})
        {
            const double w0 = 2.0 * kPi * (highPass ? band.highPassHz : lowPassHz) / aSampleRate;
            const double cosine = std::cos(w0);
            const double alpha = std::sin(w0) / (2.0 * q);
            const double a0 = 1.0 + alpha;

            Biquad& stage = m_stages[m_stageCount++];
            const double edge = highPass ? (1.0 + cosine) : (1.0 - cosine);
            stage.b0 = edge / 2.0 / a0;
            stage.b1 = (highPass ? -edge : edge) / a0;
            stage.b2 = edge / 2.0 / a0;
            stage.a1 = -2.0 * cosine / a0;
            stage.a2 = (1.0 - alpha) / a0;
        }
    }
}

void Filter::Process(uint8_t* aPcm, size_t aBytes)
{
    if (m_stageCount == 0)
    {
        return;
    }
    for (size_t offset = 0; offset + 1 < aBytes; offset += 2)
    {
        int16_t sample = 0;
        std::memcpy(&sample, aPcm + offset, sizeof(sample));

        double value = sample / 32768.0;
        for (int i = 0; i < m_stageCount; ++i)
        {
            value = m_stages[i].Step(value);
        }
        if (m_drive > 0.0)
        {
            value = std::tanh(m_drive * value) / m_drive;
        }

        value = value < -1.0 ? -1.0 : (value > 1.0 ? 1.0 : value);
        sample = static_cast<int16_t>(std::lround(value * 32767.0));
        std::memcpy(aPcm + offset, &sample, sizeof(sample));
    }
}
} // namespace ainpc::radio
