import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXNN

/// Port of mlx-lm `hunyuan_v1_dense` (Hy-MT2 / HunYuanDenseV1).
private final class DynamicNTKAlphaRoPE: Module, OffsetLayer, ArrayOffsetLayer {
    let dims: Int
    let _freqs: MLXArray

    init(dims: Int, base: Float, scalingAlpha: Float) {
        self.dims = dims
        let adjusted = base * pow(scalingAlpha, Float(dims) / Float(dims - 2))
        let indices = MLXArray(stride(from: 0, to: dims, by: 2)).asType(.float32)
        self._freqs = MLX.pow(adjusted, indices / Float(dims))
    }

    func callAsFunction(_ x: MLXArray, offset: Int = 0) -> MLXArray {
        MLXFast.RoPE(
            x,
            dimensions: dims,
            traditional: false,
            base: nil,
            scale: 1.0,
            offset: offset,
            freqs: _freqs
        )
    }

    func callAsFunction(_ x: MLXArray, offset: MLXArray) -> MLXArray {
        MLXFast.RoPE(
            x,
            dimensions: dims,
            traditional: false,
            base: nil,
            scale: 1.0,
            offset: offset,
            freqs: _freqs
        )
    }
}

private class HunyuanAttention: Module {
    let args: HunyuanV1DenseConfiguration
    let scale: Float
    let useQkNorm: Bool

    @ModuleInfo(key: "q_proj") var wq: Linear
    @ModuleInfo(key: "k_proj") var wk: Linear
    @ModuleInfo(key: "v_proj") var wv: Linear
    @ModuleInfo(key: "o_proj") var wo: Linear
    @ModuleInfo(key: "query_layernorm") var queryNorm: RMSNorm?
    @ModuleInfo(key: "key_layernorm") var keyNorm: RMSNorm?

    let rope: DynamicNTKAlphaRoPE

    init(_ args: HunyuanV1DenseConfiguration) {
        self.args = args
        let dim = args.hiddenSize
        let heads = args.attentionHeads
        let kvHeads = args.kvHeads
        let headDim = args.headDim
        self.scale = pow(Float(headDim), -0.5)
        self.useQkNorm = args.useQkNorm

        _wq.wrappedValue = Linear(dim, heads * headDim, bias: args.attentionBias)
        _wk.wrappedValue = Linear(dim, kvHeads * headDim, bias: args.attentionBias)
        _wv.wrappedValue = Linear(dim, kvHeads * headDim, bias: args.attentionBias)
        _wo.wrappedValue = Linear(heads * headDim, dim, bias: args.attentionBias)

        if args.useQkNorm {
            _queryNorm.wrappedValue = RMSNorm(dimensions: headDim, eps: args.rmsNormEps)
            _keyNorm.wrappedValue = RMSNorm(dimensions: headDim, eps: args.rmsNormEps)
        }

        let alpha = args.ropeScaling?["alpha"]?.asFloat() ?? 1.0
        self.rope = DynamicNTKAlphaRoPE(dims: headDim, base: args.ropeTheta, scalingAlpha: alpha)
    }

    func callAsFunction(
        _ x: MLXArray,
        mask: MLXFast.ScaledDotProductAttentionMaskMode,
        cache: KVCache?
    ) -> MLXArray {
        let (B, L) = (x.dim(0), x.dim(1))

        var queries = wq(x).reshaped(B, L, args.attentionHeads, -1).transposed(0, 2, 1, 3)
        var keys = wk(x).reshaped(B, L, args.kvHeads, -1).transposed(0, 2, 1, 3)
        let values = wv(x).reshaped(B, L, args.kvHeads, -1).transposed(0, 2, 1, 3)

        let offset = cache?.ropeOffset
        queries = applyRotaryPosition(rope, to: queries, offset: offset)
        keys = applyRotaryPosition(rope, to: keys, offset: offset)

        if useQkNorm, let queryNorm, let keyNorm {
            queries = queryNorm(queries)
            keys = keyNorm(keys)
        }

        let output = attentionWithCacheUpdate(
            queries: queries,
            keys: keys,
            values: values,
            cache: cache,
            scale: scale,
            mask: mask
        )
        .transposed(0, 2, 1, 3)
        .reshaped(B, L, -1)

        return wo(output)
    }
}

private class HunyuanMLP: Module, UnaryLayer {
    @ModuleInfo(key: "gate_proj") var gate: Linear
    @ModuleInfo(key: "down_proj") var down: Linear
    @ModuleInfo(key: "up_proj") var up: Linear

    init(dimensions: Int, hiddenDimensions: Int) {
        _gate.wrappedValue = Linear(dimensions, hiddenDimensions, bias: false)
        _down.wrappedValue = Linear(hiddenDimensions, dimensions, bias: false)
        _up.wrappedValue = Linear(dimensions, hiddenDimensions, bias: false)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        down(silu(gate(x)) * up(x))
    }
}

private class HunyuanBlock: Module {
    @ModuleInfo(key: "self_attn") var attention: HunyuanAttention
    let mlp: HunyuanMLP
    @ModuleInfo(key: "input_layernorm") var inputLayerNorm: RMSNorm
    @ModuleInfo(key: "post_attention_layernorm") var postAttentionLayerNorm: RMSNorm

    init(_ args: HunyuanV1DenseConfiguration) {
        _attention.wrappedValue = HunyuanAttention(args)
        self.mlp = HunyuanMLP(dimensions: args.hiddenSize, hiddenDimensions: args.intermediateSize)
        _inputLayerNorm.wrappedValue = RMSNorm(dimensions: args.hiddenSize, eps: args.rmsNormEps)
        _postAttentionLayerNorm.wrappedValue = RMSNorm(
            dimensions: args.hiddenSize, eps: args.rmsNormEps)
    }

    func callAsFunction(
        _ x: MLXArray,
        mask: MLXFast.ScaledDotProductAttentionMaskMode,
        cache: KVCache?
    ) -> MLXArray {
        var r = attention(inputLayerNorm(x), mask: mask, cache: cache)
        let h = x + r
        r = mlp(postAttentionLayerNorm(h))
        return h + r
    }
}

private class HunyuanV1DenseInner: Module {
    @ModuleInfo(key: "embed_tokens") var embedTokens: Embedding
    fileprivate let layers: [HunyuanBlock]
    let norm: RMSNorm

    init(_ args: HunyuanV1DenseConfiguration) {
        _embedTokens.wrappedValue = Embedding(
            embeddingCount: args.vocabularySize, dimensions: args.hiddenSize)
        self.layers = (0 ..< args.hiddenLayers).map { _ in HunyuanBlock(args) }
        self.norm = RMSNorm(dimensions: args.hiddenSize, eps: args.rmsNormEps)
    }

    func callAsFunction(_ inputs: MLXArray, cache: [KVCache]? = nil) -> MLXArray {
        var h = embedTokens(inputs)
        let mask = createAttentionMask(h: h, cache: cache?.first)
        for (i, layer) in layers.enumerated() {
            h = layer(h, mask: mask, cache: cache?[i])
        }
        return norm(h)
    }
}

public final class HunyuanV1DenseModel: Module, LLMModel, KVCacheDimensionProvider {
    public let vocabularySize: Int
    public let kvHeads: [Int]
    fileprivate let model: HunyuanV1DenseInner
    private let configuration: HunyuanV1DenseConfiguration
    @ModuleInfo(key: "lm_head") var lmHead: Linear?

    public init(_ args: HunyuanV1DenseConfiguration) {
        self.configuration = args
        self.vocabularySize = args.vocabularySize
        self.kvHeads = (0 ..< args.hiddenLayers).map { _ in args.kvHeads }
        self.model = HunyuanV1DenseInner(args)
        if !args.tieWordEmbeddings {
            _lmHead.wrappedValue = Linear(args.hiddenSize, args.vocabularySize, bias: false)
        }
    }

    public func callAsFunction(_ inputs: MLXArray, cache: [KVCache]?) -> MLXArray {
        var out = model(inputs, cache: cache)
        if let lmHead {
            out = lmHead(out)
        } else {
            out = tiedHead(out)
        }
        return out
    }

    private func tiedHead(_ hidden: MLXArray) -> MLXArray {
        if let quantized = model.embedTokens as? QuantizedEmbedding {
            return quantizedAsLinearChunked(hidden, embedding: quantized)
        }
        return model.embedTokens.asLinear(hidden)
    }

    /// `quantizedMM` zeros rows past 65536 on this 120818-row table.
    /// Chunk so we never `eval` a ~500MB bf16 copy that Metal keeps after unload.
    private func quantizedAsLinearChunked(
        _ hidden: MLXArray,
        embedding: QuantizedEmbedding
    ) -> MLXArray {
        let vocab = configuration.vocabularySize
        let maxRows = 32_768
        if vocab <= maxRows {
            return embedding.asLinear(hidden)
        }
        var parts: [MLXArray] = []
        var start = 0
        while start < vocab {
            let end = min(start + maxRows, vocab)
            parts.append(
                quantizedMM(
                    hidden,
                    embedding.weight[start..<end],
                    scales: embedding.scales[start..<end],
                    biases: embedding.biases.map { $0[start..<end] },
                    transpose: true,
                    groupSize: embedding.groupSize,
                    bits: embedding.bits,
                    mode: embedding.mode
                )
            )
            start = end
        }
        return concatenated(parts, axis: -1)
    }

    func releaseScratch() {}

    public func sanitize(weights: [String: MLXArray]) -> [String: MLXArray] {
        var weights = weights
        if configuration.tieWordEmbeddings {
            weights["lm_head.weight"] = nil
        }
        return weights
    }

    public var loraLayers: [Module] { model.layers }
}

public struct HunyuanV1DenseConfiguration: Codable, Sendable {
    var hiddenSize: Int
    var hiddenLayers: Int
    var intermediateSize: Int
    var attentionHeads: Int
    var rmsNormEps: Float
    var vocabularySize: Int
    var kvHeads: Int
    var ropeTheta: Float
    var headDim: Int
    var ropeScaling: [String: StringOrNumber]?
    var tieWordEmbeddings: Bool
    var attentionBias: Bool
    var useQkNorm: Bool
    var maxPositionEmbeddings: Int

    enum CodingKeys: String, CodingKey {
        case hiddenSize = "hidden_size"
        case hiddenLayers = "num_hidden_layers"
        case intermediateSize = "intermediate_size"
        case attentionHeads = "num_attention_heads"
        case rmsNormEps = "rms_norm_eps"
        case vocabularySize = "vocab_size"
        case kvHeads = "num_key_value_heads"
        case ropeTheta = "rope_theta"
        case headDim = "head_dim"
        case ropeScaling = "rope_scaling"
        case tieWordEmbeddings = "tie_word_embeddings"
        case attentionBias = "attention_bias"
        case useQkNorm = "use_qk_norm"
        case maxPositionEmbeddings = "max_position_embeddings"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hiddenSize = try container.decode(Int.self, forKey: .hiddenSize)
        hiddenLayers = try container.decode(Int.self, forKey: .hiddenLayers)
        intermediateSize = try container.decode(Int.self, forKey: .intermediateSize)
        attentionHeads = try container.decode(Int.self, forKey: .attentionHeads)
        rmsNormEps = try container.decode(Float.self, forKey: .rmsNormEps)
        vocabularySize = try container.decode(Int.self, forKey: .vocabularySize)
        kvHeads = try container.decode(Int.self, forKey: .kvHeads)
        ropeTheta = try container.decodeIfPresent(Float.self, forKey: .ropeTheta) ?? 10_000
        if let headDim = try container.decodeIfPresent(Int.self, forKey: .headDim) {
            self.headDim = headDim
        } else {
            self.headDim = hiddenSize / attentionHeads
        }
        ropeScaling = try container.decodeIfPresent([String: StringOrNumber].self, forKey: .ropeScaling)
        tieWordEmbeddings = try container.decodeIfPresent(Bool.self, forKey: .tieWordEmbeddings) ?? false
        attentionBias = try container.decodeIfPresent(Bool.self, forKey: .attentionBias) ?? false
        useQkNorm = try container.decodeIfPresent(Bool.self, forKey: .useQkNorm) ?? true
        maxPositionEmbeddings =
            try container.decodeIfPresent(Int.self, forKey: .maxPositionEmbeddings) ?? 32_768
    }
}
