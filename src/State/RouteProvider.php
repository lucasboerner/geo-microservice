<?php

declare(strict_types=1);

namespace App\State;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProviderInterface;
use App\ApiResource\Route;
use App\Client\OsrmClient;
use App\Client\PhotonClient;
use App\Dto\Coordinate;
use Symfony\Component\HttpFoundation\RequestStack;
use Symfony\Component\HttpKernel\Exception\BadRequestHttpException;
use Symfony\Component\HttpKernel\Exception\HttpException;
use Symfony\Component\HttpKernel\Exception\UnprocessableEntityHttpException;
use Symfony\Contracts\HttpClient\Exception\ExceptionInterface;

/**
 * @implements ProviderInterface<Route>
 */
final readonly class RouteProvider implements ProviderInterface
{
    private const string COORDINATE_PATTERN = '/^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/';

    public function __construct(
        private PhotonClient $photon,
        private OsrmClient $osrm,
        private RequestStack $requestStack,
    ) {
    }

    /**
     * @throws ExceptionInterface
     */
    public function provide(Operation $operation, array $uriVariables = [], array $context = []): Route
    {
        $request = $this->requestStack->getCurrentRequest();

        $from = trim((string) $request?->query->get('from', ''));
        $to = trim((string) $request?->query->get('to', ''));
        if ('' === $from || '' === $to) {
            throw new BadRequestHttpException('Query parameters "from" and "to" are required.');
        }

        $origin = $this->resolve($from);
        $destination = $this->resolve($to);

        try {
            return $this->osrm->route($origin, $destination);
        } catch (ExceptionInterface|\RuntimeException $exception) {
            throw new HttpException(502, 'Routing backend unavailable.', $exception);
        }
    }

    /**
     * @throws ExceptionInterface
     */
    private function resolve(string $value): Coordinate
    {
        if (1 === preg_match(self::COORDINATE_PATTERN, $value, $matches)) {
            return new Coordinate((float) $matches[1], (float) $matches[2]);
        }

        $places = $this->photon->geocode($value, null, 1);
        if ([] === $places) {
            throw new UnprocessableEntityHttpException(\sprintf('Address "%s" could not be geocoded.', $value));
        }

        return new Coordinate($places[0]->lat, $places[0]->lon);
    }
}
