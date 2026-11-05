import Foundation

/// Escolhe, entre os buffers de entrada do aggregate device, o que carrega o áudio do tap.
///
/// O aggregate inclui a saída como sub-device. Se ela tiver entrada (microfone do AirPods, por exemplo),
/// os buffers de entrada deixam de ser só o do tap, e a ordem entre eles não é documentada.
/// Por isso a escolha é pelo formato (número de canais), nunca por posição. Se não houver
/// exatamente um candidato, falha em vez de arriscar mandar o microfone pra saída.
public enum BufferSelection {
    public static func tapInputIndex(inputChannels: [Int], tapChannels: Int) throws -> Int {
        let candidates = inputChannels.indices.filter { inputChannels[$0] == tapChannels }
        switch candidates.count {
        case 1:
            return candidates[0]
        case 0:
            throw AudioError("nenhum buffer de entrada com \(tapChannels) canais (layout: \(inputChannels))")
        default:
            throw AudioError("buffer do tap ambíguo: \(candidates.count) buffers com \(tapChannels) canais (layout: \(inputChannels))")
        }
    }
}
