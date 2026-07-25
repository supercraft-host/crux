// Weekly leaderboard, end-to-end.
//
// Attach to any GameObject in a scene; configure the inspector fields.
// See sdks/unity/README.md for installation.
using System;
using Supercraft.Crux;
using UnityEngine;

public class Leaderboard : MonoBehaviour
{
    [SerializeField] private string baseUrl       = "https://crux.supercraft.host";
    [SerializeField] private string projectId     = "<PROJECT_ID>";
    [SerializeField] private string environmentId = "<ENVIRONMENT_ID>";
    [SerializeField] private string apiKey        = "<API_KEY>";
    [SerializeField] private string leaderboardId = "weekly";

    private async void Start()
    {
        try
        {
            var gsb = CruxClient.ForPlayer(baseUrl, projectId, environmentId, apiKey);

            var auth = await gsb.LoginAnonymousAsync();
            Debug.Log($"logged in as {auth.player_id}");

            int score = UnityEngine.Random.Range(0, 10_000);
            await gsb.SubmitScoreAsync(leaderboardId, auth.player_id, score);
            Debug.Log($"submitted {score}");

            var top = await gsb.GetTopAsync(leaderboardId, 10);
            Debug.Log($"top {top.Length}:");
            foreach (var e in top)
                Debug.Log($"  #{e.rank,2} {e.player_id} → {e.score}");

            var me = await gsb.GetPlayerStandingAsync(leaderboardId, auth.player_id);
            Debug.Log(me != null ? $"my standing: #{me.rank}" : "my standing: unranked");

            var neighbours = await gsb.GetAroundPlayerAsync(leaderboardId, auth.player_id, 2);
            Debug.Log("neighbours (±2):");
            foreach (var e in neighbours)
                Debug.Log($"  #{e.rank} {e.player_id} → {e.score}");
        }
        catch (Exception ex)
        {
            Debug.LogError(ex);
        }
    }
}
