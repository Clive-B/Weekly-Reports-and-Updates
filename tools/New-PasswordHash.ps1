param(
    [Parameter(Mandatory = $true)]
    [string]$Password
)

$salt = New-Object byte[] 16
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($salt)
$rng.Dispose()

$derive = [System.Security.Cryptography.Rfc2898DeriveBytes]::new(
    $Password,
    $salt,
    200000,
    [System.Security.Cryptography.HashAlgorithmName]::SHA256
)
$hash = $derive.GetBytes(32)
$derive.Dispose()

"pbkdf2-sha256:200000:{0}:{1}" -f [Convert]::ToBase64String($salt), [Convert]::ToBase64String($hash)
