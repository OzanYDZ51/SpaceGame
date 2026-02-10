export interface Player {
  id: string;
  username: string;
  email: string;
  current_ship_id: string;
  credits: number;
  kills: number;
  deaths: number;
  created_at: string;
}

export interface AuthResponse {
  access_token: string;
  refresh_token: string;
  player: Player;
}

export interface RefreshResponse {
  access_token: string;
  refresh_token: string;
}

export interface ChangelogEntry {
  id: number;
  version: string;
  summary: string;
  is_major: boolean;
  created_at: string;
}

export interface ReleaseInfo {
  version: string;
  download_url: string;
  size: number;
}

export interface UpdatesResponse {
  game: ReleaseInfo | null;
  launcher: ReleaseInfo | null;
}

export interface ApiError {
  error: string;
}
