<?php

declare(strict_types=1);

namespace App\ApiResource;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Get;
use App\Dto\Coordinate;
use App\State\RouteProvider;

/**
 * @phpstan-type OsrmRoute array{distance?: float, duration?: float, geometry?: mixed}
 */
#[ApiResource(
    shortName: 'Route',
    operations: [
        new Get(
            uriTemplate: '/route',
            provider: RouteProvider::class,
        ),
    ],
)]
final class Route
{
    public function __construct(
        public Coordinate $from,
        public Coordinate $to,
        public float $distanceInMeters = 0.0,
        public float $durationInSeconds = 0.0,
        public mixed $geometry = null,
    ) {
    }

    /**
     * @param OsrmRoute $route
     */
    public static function fromArray(Coordinate $from, Coordinate $to, array $route): self
    {
        return new self(
            from: $from,
            to: $to,
            distanceInMeters: $route['distance'] ?? 0.0,
            durationInSeconds: $route['duration'] ?? 0.0,
            geometry: $route['geometry'] ?? null,
        );
    }
}
