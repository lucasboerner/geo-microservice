<?php

declare(strict_types=1);

namespace App\Client;

use App\ApiResource\Route;
use App\Dto\Coordinate;
use Symfony\Contracts\HttpClient\Exception\ExceptionInterface;
use Symfony\Contracts\HttpClient\HttpClientInterface;

/**
 * @phpstan-import-type OsrmRoute from Route
 */
final readonly class OsrmClient
{
    public function __construct(private HttpClientInterface $osrmClient)
    {
    }

    /**
     * @throws ExceptionInterface
     * @throws \RuntimeException
     */
    public function route(Coordinate $from, Coordinate $to): Route
    {
        $path = sprintf('/route/v1/driving/%s,%s;%s,%s', $from->lon, $from->lat, $to->lon, $to->lat);

        /** @var array{routes?: list<OsrmRoute>} $data */
        $data = $this->osrmClient
            ->request('GET', $path, ['query' => ['overview' => 'full', 'geometries' => 'geojson']])
            ->toArray();

        $routes = $data['routes'] ?? [];
        if ([] === $routes) {
            throw new \RuntimeException('OSRM returned no route.');
        }

        return Route::fromArray($from, $to, $routes[0]);
    }
}
