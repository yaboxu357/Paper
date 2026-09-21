import torch
import torch.nn as nn
import torch.nn.functional as F
from layers.Transformer_Encoder import Encoder, EncoderLayer
from layers.SWTAttention_Family import GeomAttentionLayer, GeomAttention
from layers.Embed import DataEmbedding_inverted


class Model(nn.Module):
    def __init__(self, configs):
        super(Model, self).__init__()
        self.seq_len = configs.seq_len
        self.pred_len = configs.pred_len
        self.output_attention = configs.output_attention
        self.use_norm = configs.use_norm
        self.geomattn_dropout = configs.geomattn_dropout
        self.alpha = configs.alpha
        self.kernel_size = configs.kernel_size
        self.enc_in = configs.enc_in
        self.d_model = configs.d_model
        self.freq = configs.freq.lower()
        self.use_embedding_armor = bool(getattr(configs, 'use_embedding_armor', 1))
        self.armor_cycle = getattr(configs, 'armor_cycle', 24)
        self.armor_scale = getattr(configs, 'armor_scale', 1.0)

        if self.armor_cycle < 1:
            raise ValueError('armor_cycle must be positive')
        if self.armor_scale < 0.0:
            raise ValueError('armor_scale must be non-negative')

        enc_embedding = DataEmbedding_inverted(configs.seq_len, configs.d_model, 
                                               configs.embed, configs.freq, configs.dropout)
        self.enc_embedding = enc_embedding

        encoder = Encoder(
            [  
                EncoderLayer(
                    GeomAttentionLayer(
                        GeomAttention(
                            False, configs.factor, attention_dropout=configs.dropout, 
                            output_attention=configs.output_attention, alpha=self.alpha
                        ),
                        configs.d_model, 
                        requires_grad=configs.requires_grad, 
                        wv=configs.wv, 
                        m=configs.m, 
                        d_channel=configs.dec_in, 
                        kernel_size=self.kernel_size, 
                        geomattn_dropout=self.geomattn_dropout
                    ),
                    configs.d_model,
                    configs.d_ff,
                    dropout=configs.dropout,
                    activation=configs.activation,
                ) for l in range(configs.e_layers) 
            ],
            norm_layer=torch.nn.LayerNorm(configs.d_model)
        )
        self.encoder = encoder

        if self.use_embedding_armor:
            self.channel_embedding = nn.Parameter(
                torch.zeros(configs.enc_in, configs.d_model)
            )
            self.phase_embedding = nn.Embedding(self.armor_cycle, configs.d_model)
            self.joint_embedding = nn.Embedding(
                self.armor_cycle, configs.enc_in * configs.d_model
            )
            self.armor_dropout = nn.Dropout(getattr(configs, 'armor_dropout', 0.0))
            nn.init.xavier_normal_(self.channel_embedding)
            nn.init.xavier_normal_(self.phase_embedding.weight)
            nn.init.xavier_normal_(self.joint_embedding.weight)

        projector = nn.Linear(configs.d_model, self.pred_len, bias=True)
        self.projector = projector

    def _phase_index(self, x_mark):
        if x_mark is None:
            return torch.zeros(1, dtype=torch.long, device=self.channel_embedding.device)

        last_mark = x_mark[:, -1]
        if self.freq.startswith('t') or 'min' in self.freq:
            minute = torch.round((last_mark[:, 0] + 0.5) * 59).long()
            hour = torch.round((last_mark[:, 1] + 0.5) * 23).long()
            phase = hour * 4 + torch.div(minute, 15, rounding_mode='floor')
        elif self.freq.startswith('h'):
            hour = torch.round((last_mark[:, 0] + 0.5) * 23).long()
            if self.armor_cycle == 168 and last_mark.shape[-1] > 1:
                weekday = torch.round((last_mark[:, 1] + 0.5) * 6).long()
                phase = weekday * 24 + hour
            else:
                phase = hour
        else:
            phase = torch.round(
                (last_mark[:, 0] + 0.5) * (self.armor_cycle - 1)
            ).long()

        return (phase + 1).remainder(self.armor_cycle)

    def _apply_embedding_armor(self, enc_out, x_mark):
        batch_size, channels, _ = enc_out.shape
        phase = self._phase_index(x_mark)
        if phase.shape[0] == 1 and batch_size != 1:
            phase = phase.expand(batch_size)

        channel_emb = self.channel_embedding[:channels].unsqueeze(0)
        phase_emb = self.phase_embedding(phase).unsqueeze(1)
        joint_emb = self.joint_embedding(phase).reshape(
            batch_size, self.enc_in, self.d_model
        )[:, :channels]
        armor = self.armor_dropout(channel_emb + phase_emb + joint_emb)
        return enc_out + self.armor_scale * armor

    def forecast(self, x_enc, x_mark_enc, x_dec, x_mark_dec):
        if self.use_norm:
            means = x_enc.mean(1, keepdim=True).detach()
            x_enc = x_enc - means
            stdev = torch.sqrt(torch.var(x_enc, dim=1, keepdim=True, unbiased=False) + 1e-5)
            # x_enc /= stdev
            x_enc = x_enc / stdev

        _, _, N = x_enc.shape

        encoder = self.encoder
        projector = self.projector
        # Linear Projection             B L N -> B L' (pseudo temporal tokens) N 
        enc_out = self.enc_embedding(x_enc, None)
        if self.use_embedding_armor:
            enc_out = self._apply_embedding_armor(enc_out, x_mark_enc)
        # SimpleTM Layer                B L' N -> B L' N 
        enc_out, attns = encoder(enc_out, attn_mask=None)

        # Output Projection             B L' N -> B H (Horizon) N
        dec_out = projector(enc_out).permute(0, 2, 1)[:, :, :N]
        if self.use_norm:
            dec_out = dec_out * (stdev[:, 0, :].unsqueeze(1).repeat(1, self.pred_len, 1))
            dec_out = dec_out + (means[:, 0, :].unsqueeze(1).repeat(1, self.pred_len, 1))

        return dec_out, attns


    def forward(self, x_enc, x_mark_enc, x_dec, x_mark_dec, mask=None):
        dec_out, attns = self.forecast(x_enc, x_mark_enc, x_dec, x_mark_dec)
        return dec_out, attns 
