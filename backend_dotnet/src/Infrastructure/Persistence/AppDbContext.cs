using Domain.Entities;
using Infrastructure.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;

namespace Infrastructure.Persistence;

public class AppDbContext : IdentityDbContext<ApplicationUser>
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options)
    {
    }

    public DbSet<UserTranscriptionPreference> UserTranscriptionPreferences => Set<UserTranscriptionPreference>();
    public DbSet<TranscriptionJob> TranscriptionJobs => Set<TranscriptionJob>();
    public DbSet<TranscriptionJobOutput> TranscriptionJobOutputs => Set<TranscriptionJobOutput>();

    protected override void OnModelCreating(ModelBuilder builder)
    {
        base.OnModelCreating(builder);

        builder.Entity<UserTranscriptionPreference>(e =>
        {
            e.ToTable("UserTranscriptionPreferences");

            e.HasKey(x => x.Id);

            e.Property(x => x.UserId).IsRequired();
            e.Property(x => x.SourceTypeDefault).HasMaxLength(32).IsRequired();
            e.Property(x => x.Model).HasMaxLength(64).IsRequired();
            e.Property(x => x.Task).HasMaxLength(32).IsRequired();
            e.Property(x => x.Language).HasMaxLength(16).IsRequired();
            e.Property(x => x.OutputFormat).HasMaxLength(16).IsRequired();
            e.Property(x => x.DevicePreference).HasMaxLength(32).IsRequired();
            e.Property(x => x.ComputeType).HasMaxLength(32).IsRequired();
            e.Property(x => x.SubtitleStyle).HasMaxLength(64).IsRequired();
            e.Property(x => x.UseAdvancedAlignment).HasMaxLength(16).IsRequired();
            e.Property(x => x.QualityProfile).HasMaxLength(16).IsRequired();
            e.Property(x => x.ContentMode).HasMaxLength(24).IsRequired();
            e.Property(x => x.SpeakerStyleMode).HasMaxLength(24).IsRequired();
            e.Property(x => x.StyleIntensity).HasMaxLength(24).IsRequired();
            e.Property(x => x.RenderedPreviewMode).HasMaxLength(24).IsRequired();
            e.Property(x => x.AnimeSongLayoutMode).HasMaxLength(48).IsRequired();
            e.Property(x => x.KaraokeGranularity).HasMaxLength(16).IsRequired();
            e.Property(x => x.UpdatedAtUtc).IsRequired();

            e.HasIndex(x => x.UserId).IsUnique();
        });

        builder.Entity<TranscriptionJob>(e =>
        {
            e.ToTable("TranscriptionJobs");

            e.HasKey(x => x.Id);

            e.Property(x => x.UserId).IsRequired();
            e.Property(x => x.SourceType).HasMaxLength(32).IsRequired();
            e.Property(x => x.SourceValue).HasMaxLength(2048).IsRequired();

            e.Property(x => x.Model).HasMaxLength(64).IsRequired();
            e.Property(x => x.Task).HasMaxLength(32).IsRequired();
            e.Property(x => x.Language).HasMaxLength(16).IsRequired();
            e.Property(x => x.OutputFormat).HasMaxLength(16).IsRequired();

            e.Property(x => x.DevicePreference).HasMaxLength(32).IsRequired();
            e.Property(x => x.ComputeType).HasMaxLength(32).IsRequired();
            e.Property(x => x.SubtitleStyle).HasMaxLength(64).IsRequired();
            e.Property(x => x.UseAdvancedAlignment).HasMaxLength(16).IsRequired();
            e.Property(x => x.QualityProfile).HasMaxLength(16).IsRequired();
            e.Property(x => x.ContentMode).HasMaxLength(24).IsRequired();
            e.Property(x => x.SpeakerStyleMode).HasMaxLength(24).IsRequired();
            e.Property(x => x.StyleIntensity).HasMaxLength(24).IsRequired();
            e.Property(x => x.RenderedPreviewMode).HasMaxLength(24).IsRequired();
            e.Property(x => x.AnimeSongLayoutMode).HasMaxLength(48).IsRequired();
            e.Property(x => x.KaraokeGranularity).HasMaxLength(16).IsRequired();

            e.Property(x => x.Status).HasMaxLength(32).IsRequired();
            e.Property(x => x.CurrentStage).HasMaxLength(32).IsRequired();
            e.Property(x => x.ErrorMessage).HasMaxLength(4000);
            e.Property(x => x.LanguageDetected).HasMaxLength(16);
            e.Property(x => x.StyleSource).HasMaxLength(32);
            e.Property(x => x.DetectedContentType).HasMaxLength(24);
            e.Property(x => x.SpeakerModeApplied).HasMaxLength(24);
            e.Property(x => x.KaraokeModeApplied).HasMaxLength(16);

            e.Property(x => x.CreatedAtUtc).IsRequired();

            e.HasIndex(x => x.UserId);
            e.HasIndex(x => x.Status);
            e.HasIndex(x => x.CreatedAtUtc);

            e.HasMany(x => x.Outputs)
                .WithOne(x => x.Job)
                .HasForeignKey(x => x.JobId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        builder.Entity<TranscriptionJobOutput>(e =>
        {
            e.ToTable("TranscriptionJobOutputs");

            e.HasKey(x => x.Id);

            e.Property(x => x.OutputType).HasMaxLength(32).IsRequired();
            e.Property(x => x.FilePath).HasMaxLength(2048);
            e.Property(x => x.CreatedAtUtc).IsRequired();

            e.HasIndex(x => x.JobId);
            e.HasIndex(x => x.OutputType);
        });
    }
}
